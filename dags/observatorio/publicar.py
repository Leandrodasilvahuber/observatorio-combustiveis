"""Task 5: gerar o resumo do período a partir dos marts e publicar no S3."""

import json
import logging
from datetime import datetime, timezone
from decimal import Decimal

from observatorio import config

log = logging.getLogger(__name__)

MELHORES_PARA_ETANOL = 10

SQL_FATO = "select count(*) from marts.fct_precos"

SQL_UF = """
    select periodo_inicio, periodo_fim, uf, produto, unidade_medida,
           preco_medio, preco_min, preco_max, coletas
    from marts.agg_uf_periodo
    order by produto, uf
"""

SQL_ETANOL = """
    select uf, municipio, preco_medio_gasolina, preco_medio_etanol, razao, etanol_compensa
    from marts.agg_etanol_compensa
    order by razao, uf, municipio
"""


def _numero(valor):
    return float(valor) if isinstance(valor, Decimal) else valor


def montar_resumo(linhas_uf: list[dict], linhas_etanol: list[dict], gerado_em: datetime) -> dict:
    if not linhas_uf:
        raise ValueError("agg_uf_periodo vazio: nada a publicar")

    primeira = linhas_uf[0]
    inicio, fim = primeira["periodo_inicio"], primeira["periodo_fim"]
    return {
        # dias explícito: a janela dos marts já mudou (16 -> 10) e o histórico
        # em resultados/ mistura os dois tamanhos.
        "periodo": {"inicio": inicio.isoformat(), "fim": fim.isoformat(), "dias": (fim - inicio).days + 1},
        "gerado_em": gerado_em.isoformat(timespec="seconds"),
        "preco_medio_por_uf": [
            {
                "uf": l["uf"],
                "produto": l["produto"],
                "unidade": l["unidade_medida"],
                "preco_medio": _numero(l["preco_medio"]),
                "preco_min": _numero(l["preco_min"]),
                "preco_max": _numero(l["preco_max"]),
                "coletas": l["coletas"],
            }
            for l in linhas_uf
        ],
        "etanol_vs_gasolina": {
            "municipios_analisados": len(linhas_etanol),
            "municipios_onde_etanol_compensa": sum(1 for l in linhas_etanol if l["etanol_compensa"]),
            "melhores_para_etanol": [
                {
                    "uf": l["uf"],
                    "municipio": l["municipio"],
                    "gasolina": _numero(l["preco_medio_gasolina"]),
                    "etanol": _numero(l["preco_medio_etanol"]),
                    "razao": _numero(l["razao"]),
                    "etanol_compensa": l["etanol_compensa"],
                }
                for l in linhas_etanol[:MELHORES_PARA_ETANOL]
            ],
        },
    }


def _consultar(conn, sql: str) -> list[dict]:
    with conn.cursor() as cur:
        cur.execute(sql)
        colunas = [c.name for c in cur.description]
        return [dict(zip(colunas, linha, strict=True)) for linha in cur.fetchall()]


def publicar_resultados(conn, s3=None) -> list[str]:
    """Grava resultados/<fim>.json e depois resultados/latest.json, para que o
    latest nunca aponte para um período que não existe."""
    with conn.cursor() as cur:
        cur.execute(SQL_FATO)
        if cur.fetchone()[0] == 0:
            raise ValueError("marts.fct_precos vazio: nada a publicar")

    resumo = montar_resumo(
        _consultar(conn, SQL_UF),
        _consultar(conn, SQL_ETANOL),
        datetime.now(timezone.utc),
    )
    corpo = json.dumps(resumo, ensure_ascii=False, indent=2).encode()

    s3 = s3 or config.s3_client()
    bucket = config.bucket()
    chaves = [
        f"{config.PREFIXO_RESULTADOS}/{resumo['periodo']['fim']}.json",
        f"{config.PREFIXO_RESULTADOS}/latest.json",
    ]
    for chave in chaves:
        s3.put_object(
            Bucket=bucket,
            Key=chave,
            Body=corpo,
            ContentType="application/json; charset=utf-8",
        )
        log.info("s3://%s/%s publicado (%d bytes)", bucket, chave, len(corpo))

    return chaves
