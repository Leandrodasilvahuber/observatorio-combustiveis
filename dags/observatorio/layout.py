"""Layout dos CSVs da ANP: identificação de colunas pelo nome, não pela posição."""

import re
import unicodedata

# Colunas da tabela raw.precos_anp, na ordem do COPY.
COLUNAS_RAW = [
    "regiao",
    "uf",
    "municipio",
    "revenda",
    "cnpj",
    "nome_rua",
    "numero_rua",
    "complemento",
    "bairro",
    "cep",
    "produto",
    "data_coleta",
    "valor_venda",
    "valor_compra",
    "unidade_medida",
    "bandeira",
]

COLUNAS_OBRIGATORIAS = [
    "regiao",
    "uf",
    "municipio",
    "revenda",
    "cnpj",
    "produto",
    "data_coleta",
    "valor_venda",
    "unidade_medida",
    "bandeira",
]

# Nome normalizado no arquivo da ANP -> coluna no projeto. Se a ANP renomear
# uma coluna, a task validar falha listando a ausente; basta incluir o novo
# nome aqui.
APELIDOS = {
    "regiao_sigla": "regiao",
    "regiao": "regiao",
    "estado_sigla": "uf",
    "estado": "uf",
    "uf": "uf",
    "municipio": "municipio",
    "revenda": "revenda",
    "cnpj_da_revenda": "cnpj",
    "cnpj": "cnpj",
    "nome_da_rua": "nome_rua",
    "numero_rua": "numero_rua",
    "complemento": "complemento",
    "bairro": "bairro",
    "cep": "cep",
    "produto": "produto",
    "data_da_coleta": "data_coleta",
    "valor_de_venda": "valor_venda",
    "valor_de_compra": "valor_compra",
    "unidade_de_medida": "unidade_medida",
    "bandeira": "bandeira",
}


def normalizar(nome: str) -> str:
    """'Estado - Sigla' -> 'estado_sigla'; remove BOM, acentos e espaços."""
    sem_acento = unicodedata.normalize("NFKD", nome.strip().lstrip("﻿"))
    ascii_ = sem_acento.encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "_", ascii_.lower()).strip("_")


def mapear_cabecalho(cabecalho: list[str]) -> dict[str, int]:
    """Retorna {coluna_do_projeto: posição no arquivo} para as colunas conhecidas."""
    mapa: dict[str, int] = {}
    for posicao, nome in enumerate(cabecalho):
        coluna = APELIDOS.get(normalizar(nome))
        if coluna and coluna not in mapa:
            mapa[coluna] = posicao
    return mapa


def colunas_ausentes(cabecalho: list[str]) -> list[str]:
    mapa = mapear_cabecalho(cabecalho)
    return [c for c in COLUNAS_OBRIGATORIAS if c not in mapa]
