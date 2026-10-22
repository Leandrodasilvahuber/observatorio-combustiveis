import os

import boto3

# Arquivos das últimas quatro semanas (sobreposição proposital com o ciclo de
# 10 dias). Podem ser substituídos pela Variable `anp_urls` do Airflow.
ANP_URLS_PADRAO = [
    "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/shpc/qus/ultimas-4-semanas-gasolina-etanol.csv",
    "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/shpc/qus/ultimas-4-semanas-diesel-gnv.csv",
]

PREFIXO_BRONZE = "bronze/anp"
PREFIXO_RESULTADOS = "resultados"
CONN_ID_DW = "observatorio_dw"


def bucket() -> str:
    return os.environ["OBS_BUCKET"]


def s3_client():
    # Localmente OBS_S3_ENDPOINT_URL aponta para o LocalStack; na AWS fica
    # vazio e as credenciais vêm da role da EC2.
    return boto3.client("s3", endpoint_url=os.environ.get("OBS_S3_ENDPOINT_URL") or None)
