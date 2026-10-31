"""Task 3: carregar os CSVs do bronze em raw.precos_anp via COPY."""

import csv
import io
import logging
from collections.abc import Iterable, Iterator
from pathlib import Path

from observatorio import config
from observatorio.bronze import SEPARADOR
from observatorio.layout import COLUNAS_RAW, mapear_cabecalho

log = logging.getLogger(__name__)

DDL = (Path(__file__).parent / "sql" / "raw_precos_anp.sql").read_text()
COLUNAS_COPY = COLUNAS_RAW + ["arquivo_origem"]

# Cada ciclo carrega de novo as últimas 4 semanas, e a raw não pode crescer
# para sempre (a staging a varre inteira a cada dbt build). Acima do que o
# fct_precos incremental reprocessa (35 dias); o histórico fica no fato, mas
# um --full-refresh só recupera o que ainda estiver na raw.
RETENCAO_DIAS = 45


def linhas_padronizadas(linhas: Iterable[str], arquivo_origem: str) -> Iterator[list]:
    """Reordena as colunas do CSV da ANP para o layout da raw, sem tratar valores.

    Linhas com número de colunas diferente do cabeçalho (por exemplo, um `;`
    sem aspas) são carregadas como vieram e contadas no log; os testes do dbt
    barram o deslocamento se ele afetar as colunas usadas.
    """
    leitor = csv.reader(linhas, delimiter=SEPARADOR)
    cabecalho = next(leitor)
    mapa = mapear_cabecalho(cabecalho)
    posicoes = [mapa.get(coluna) for coluna in COLUNAS_RAW]
    irregulares = 0

    for registro in leitor:
        if not any(campo.strip() for campo in registro):
            continue
        if len(registro) != len(cabecalho):
            irregulares += 1
            if irregulares <= 5:
                log.warning(
                    "%s, linha %d: %d colunas (cabeçalho tem %d)",
                    arquivo_origem,
                    leitor.line_num,
                    len(registro),
                    len(cabecalho),
                )
        valores = [registro[p] if p is not None and p < len(registro) else None for p in posicoes]
        yield valores + [arquivo_origem]

    if irregulares:
        log.warning("%s: %d linha(s) com número de colunas irregular", arquivo_origem, irregulares)


def carregar_arquivo(conn, chave: str, s3=None) -> int:
    """Recarga idempotente: apaga as linhas do mesmo arquivo e insere de novo,
    na mesma transação. `conn` é uma conexão psycopg 3."""
    s3 = s3 or config.s3_client()
    corpo = s3.get_object(Bucket=config.bucket(), Key=chave)["Body"]
    total = 0

    with io.TextIOWrapper(corpo, encoding="utf-8-sig", newline="") as texto, conn.cursor() as cur:
        cur.execute(DDL)
        cur.execute("delete from raw.precos_anp where arquivo_origem = %s", (chave,))
        apagadas = cur.rowcount
        with cur.copy(f"copy raw.precos_anp ({', '.join(COLUNAS_COPY)}) from stdin") as copy:
            for linha in linhas_padronizadas(texto, chave):
                copy.write_row(linha)
                total += 1
    conn.commit()

    log.info("%s: %d linhas carregadas (%d substituídas)", chave, total, apagadas)
    return total


def podar_raw(conn) -> int:
    """Apaga as cargas mais antigas que RETENCAO_DIAS."""
    with conn.cursor() as cur:
        cur.execute(
            "delete from raw.precos_anp where carregado_em < now() - make_interval(days => %s)",
            (RETENCAO_DIAS,),
        )
        apagadas = cur.rowcount
    conn.commit()
    log.info("raw: %d linha(s) com mais de %d dias apagadas", apagadas, RETENCAO_DIAS)
    return apagadas


def carregar_raw(conn, chaves: list[str], s3=None) -> dict[str, int]:
    s3 = s3 or config.s3_client()
    try:
        totais = {chave: carregar_arquivo(conn, chave, s3) for chave in chaves}
        podar_raw(conn)
        return totais
    except Exception:
        conn.rollback()
        raise
