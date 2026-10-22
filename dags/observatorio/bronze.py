"""Tasks 1 e 2: baixar os CSVs da ANP para o S3 bronze e validar o layout."""

import codecs
import logging
import tempfile
from datetime import date
from posixpath import basename
from urllib.parse import urlparse

import requests

from observatorio import config
from observatorio.layout import colunas_ausentes

log = logging.getLogger(__name__)

TAMANHO_MINIMO_BYTES = 1024
SEPARADOR = ";"


def chave_bronze(data_execucao: date, url: str) -> str:
    nome = basename(urlparse(url).path)
    return f"{config.PREFIXO_BRONZE}/execucao={data_execucao.isoformat()}/{nome}"


def baixar_para_bronze(urls: list[str], data_execucao: date, s3=None) -> list[str]:
    """Baixa cada URL e grava o arquivo, sem alterações, no bronze."""
    s3 = s3 or config.s3_client()
    bucket = config.bucket()
    chaves = []

    for url in urls:
        chave = chave_bronze(data_execucao, url)
        with tempfile.SpooledTemporaryFile(max_size=64 * 1024 * 1024) as arquivo:
            with requests.get(
                url,
                stream=True,
                timeout=(15, 300),
                headers={"User-Agent": "observatorio-combustiveis/1.0"},
            ) as resposta:
                resposta.raise_for_status()
                for bloco in resposta.iter_content(chunk_size=1024 * 1024):
                    arquivo.write(bloco)

            tamanho = arquivo.tell()
            if tamanho < TAMANHO_MINIMO_BYTES:
                raise ValueError(f"{url} tem só {tamanho} bytes (mínimo {TAMANHO_MINIMO_BYTES})")

            arquivo.seek(0)
            s3.upload_fileobj(arquivo, bucket, chave, ExtraArgs={"ContentType": "text/csv"})

        log.info("s3://%s/%s gravado (%d bytes)", bucket, chave, tamanho)
        chaves.append(chave)

    return chaves


def ler_cabecalho(chave: str, s3=None) -> list[str]:
    s3 = s3 or config.s3_client()
    corpo = s3.get_object(Bucket=config.bucket(), Key=chave)["Body"]
    try:
        primeira_linha = next(corpo.iter_lines())
    finally:
        corpo.close()
    return codecs.decode(primeira_linha, "utf-8-sig").split(SEPARADOR)


def validar(chaves: list[str], s3=None) -> list[str]:
    """Falha se algum arquivo não tiver todas as colunas obrigatórias."""
    s3 = s3 or config.s3_client()
    problemas = {}
    for chave in chaves:
        ausentes = colunas_ausentes(ler_cabecalho(chave, s3))
        if ausentes:
            problemas[chave] = ausentes

    if problemas:
        detalhes = "; ".join(f"{k}: {', '.join(v)}" for k, v in problemas.items())
        raise ValueError(f"Colunas obrigatórias ausentes (ajuste APELIDOS em layout.py): {detalhes}")

    log.info("%d arquivo(s) validado(s)", len(chaves))
    return chaves
