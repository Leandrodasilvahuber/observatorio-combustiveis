from observatorio.layout import COLUNAS_RAW, colunas_ausentes, mapear_cabecalho, normalizar
from observatorio.raw import linhas_padronizadas

CABECALHO_ANP = (
    "﻿Regiao - Sigla;Estado - Sigla;Municipio;Revenda;CNPJ da Revenda;Nome da Rua;"
    "Numero Rua;Complemento;Bairro;Cep;Produto;Data da Coleta;Valor de Venda;"
    "Valor de Compra;Unidade de Medida;Bandeira"
)
LINHA_ANP = (
    "S;RS;CANOAS;METROPOLITANO COMERCIO DE COMBUSTIVEIS LTDA; 88.587.589/0001-17;"
    "AVENIDA GUILHERME SCHELL;6340;;CENTRO;92310-022;GASOLINA;22/09/2026;6,39;;R$ / litro;BRANCA"
)


def test_normalizar_remove_bom_acentos_e_separadores():
    assert normalizar("﻿Regiao - Sigla") == "regiao_sigla"
    assert normalizar("  Município ") == "municipio"
    assert normalizar("Unidade de  Medida") == "unidade_de_medida"


def test_cabecalho_atual_da_anp_tem_todas_as_colunas():
    cabecalho = CABECALHO_ANP.split(";")
    assert colunas_ausentes(cabecalho) == []
    assert set(mapear_cabecalho(cabecalho)) == set(COLUNAS_RAW)


def test_coluna_obrigatoria_ausente_e_reportada():
    cabecalho = [c for c in CABECALHO_ANP.split(";") if c != "Valor de Venda"]
    assert colunas_ausentes(cabecalho) == ["valor_venda"]


def test_reordenacao_de_colunas_nao_quebra_a_carga():
    cabecalho = CABECALHO_ANP.lstrip("﻿").split(";")
    valores = LINHA_ANP.split(";")
    ordem = list(reversed(range(len(cabecalho))))
    arquivo = [
        ";".join(cabecalho[i] for i in ordem),
        ";".join(valores[i] for i in ordem),
    ]

    [linha] = list(linhas_padronizadas(arquivo, "bronze/x.csv"))
    registro = dict(zip(COLUNAS_RAW + ["arquivo_origem"], linha, strict=False))

    assert registro["uf"] == "RS"
    assert registro["cnpj"] == " 88.587.589/0001-17"  # raw guarda o valor sem tratar
    assert registro["valor_venda"] == "6,39"
    assert registro["data_coleta"] == "22/09/2026"
    assert registro["arquivo_origem"] == "bronze/x.csv"


def test_linhas_em_branco_sao_ignoradas_e_coluna_opcional_ausente_vira_nula():
    cabecalho = [c for c in CABECALHO_ANP.split(";") if c != "Valor de Compra"]
    valores = [v for i, v in enumerate(LINHA_ANP.split(";")) if i != 13]
    arquivo = [";".join(cabecalho), ";".join(valores), "", ";;;"]

    linhas = list(linhas_padronizadas(arquivo, "a.csv"))

    assert len(linhas) == 1
    assert linhas[0][COLUNAS_RAW.index("valor_compra")] is None


def test_separador_dentro_de_campo_entre_aspas_nao_desloca_colunas():
    # Caso real da ANP: complemento "LOTE: 04;" contém o separador.
    linha = (
        "CO;DF;BRASILIA;AUTO POSTO JPC DERIVADOS DE PETROLEO LTDA; 07.129.219/0001-34;"
        'QUADRA 301 RUA A CONJUNTO 2;SN;"LOTE: 04;";NORTE (AGUAS CLARAS);71901-020;'
        "GASOLINA;21/09/2026;6,59;;R$ / litro;BRANCA"
    )

    [registro] = list(linhas_padronizadas([CABECALHO_ANP, linha], "a.csv"))
    valores = dict(zip(COLUNAS_RAW, registro, strict=False))

    assert valores["complemento"] == "LOTE: 04;"
    assert valores["produto"] == "GASOLINA"
    assert valores["valor_venda"] == "6,59"
