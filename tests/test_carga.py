"""Tasks baixar_para_bronze e carregar_raw com S3, HTTP e banco falsos."""

import io
import logging

import pytest

from observatorio import bronze, raw
from observatorio.layout import COLUNAS_RAW

CSV_ANP = (
    "﻿Regiao - Sigla;Estado - Sigla;Municipio;Revenda;CNPJ da Revenda;Nome da Rua;"
    "Numero Rua;Complemento;Bairro;Cep;Produto;Data da Coleta;Valor de Venda;"
    "Valor de Compra;Unidade de Medida;Bandeira\r\n"
    "S;RS;CANOAS;POSTO A; 88.587.589/0001-17;AV X;1;;CENTRO;92310-022;GASOLINA;22/09/2026;6,39;;R$ / litro;BRANCA\r\n"
    'CO;DF;BRASILIA;POSTO B; 07.129.219/0001-34;Q 301;SN;"LOTE: 04;";NORTE;71901-020;ETANOL;21/09/2026;4,29;;R$ / litro;\r\n'  # noqa: E501 (linha do CSV da ANP)
).encode()


@pytest.fixture(autouse=True)
def bucket(monkeypatch):
    monkeypatch.setenv("OBS_BUCKET", "bucket-teste")


class CorpoFalso(io.BytesIO):
    """Imita o StreamingBody do botocore."""

    def iter_lines(self):
        return iter(self.read().splitlines())


class S3Falso:
    def __init__(self, objetos=None):
        self.objetos = dict(objetos or {})

    def upload_fileobj(self, arquivo, bucket, chave, ExtraArgs=None):
        self.objetos[chave] = arquivo.read()

    def get_object(self, Bucket, Key):
        return {"Body": CorpoFalso(self.objetos[Key])}


class RespostaFalsa:
    def __init__(self, conteudo, status=200):
        self.conteudo, self.status = conteudo, status

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def raise_for_status(self):
        if self.status >= 400:
            raise RuntimeError(f"HTTP {self.status}")

    def iter_content(self, chunk_size):
        yield self.conteudo


def test_bronze_grava_o_arquivo_sem_alteracao(monkeypatch):
    from datetime import date

    conteudo = CSV_ANP * 20  # acima do mínimo de 1 KB
    monkeypatch.setattr(bronze.requests, "get", lambda *a, **k: RespostaFalsa(conteudo))
    s3 = S3Falso()

    [chave] = bronze.baixar_para_bronze(["https://anp/x/ultimas.csv"], date(2026, 10, 21), s3)

    assert chave == "bronze/anp/execucao=2026-10-21/ultimas.csv"
    assert s3.objetos[chave] == conteudo


def test_bronze_rejeita_arquivo_pequeno_e_erro_http(monkeypatch):
    from datetime import date

    monkeypatch.setattr(bronze.requests, "get", lambda *a, **k: RespostaFalsa(b"pouco"))
    with pytest.raises(ValueError, match="mínimo"):
        bronze.baixar_para_bronze(["https://anp/x.csv"], date(2026, 10, 21), S3Falso())

    monkeypatch.setattr(bronze.requests, "get", lambda *a, **k: RespostaFalsa(CSV_ANP * 20, 503))
    with pytest.raises(RuntimeError, match="503"):
        bronze.baixar_para_bronze(["https://anp/x.csv"], date(2026, 10, 21), S3Falso())


def test_validar_lista_colunas_ausentes():
    sem_preco = CSV_ANP.replace(b"Valor de Venda", b"Preco")
    s3 = S3Falso({"ok.csv": CSV_ANP, "ruim.csv": sem_preco})

    assert bronze.validar(["ok.csv"], s3) == ["ok.csv"]
    with pytest.raises(ValueError, match="ruim.csv: valor_venda"):
        bronze.validar(["ok.csv", "ruim.csv"], s3)


class CursorFalso:
    def __init__(self, banco):
        self.banco, self.rowcount = banco, 0

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, sql, params=None):
        if sql.startswith("delete"):
            antes = len(self.banco.linhas)
            self.banco.linhas = [l for l in self.banco.linhas if l[-1] != params[0]]
            self.rowcount = antes - len(self.banco.linhas)

    def copy(self, sql):
        banco = self.banco

        class Copy:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def write_row(self, linha):
                banco.linhas.append(linha)

        return Copy()


class ConexaoFalsa:
    def __init__(self):
        self.linhas, self.commits = [], 0

    def cursor(self):
        return CursorFalso(self)

    def commit(self):
        self.commits += 1


def test_carga_raw_e_idempotente_e_respeita_aspas():
    s3 = S3Falso({"bronze/a.csv": CSV_ANP})
    conn = ConexaoFalsa()

    assert raw.carregar_raw(conn, ["bronze/a.csv"], s3) == {"bronze/a.csv": 2}
    assert raw.carregar_raw(conn, ["bronze/a.csv"], s3) == {"bronze/a.csv": 2}

    assert len(conn.linhas) == 2  # recarga substituiu, não duplicou
    registro = dict(zip(COLUNAS_RAW, conn.linhas[1], strict=False))
    assert registro["complemento"] == "LOTE: 04;"
    assert registro["bandeira"] == ""  # vazio na raw; vira SEM BANDEIRA na staging


def test_linhas_com_colunas_a_mais_geram_aviso(caplog):
    linhas = CSV_ANP.decode("utf-8-sig").splitlines()
    linhas.append("S;RS;CANOAS;POSTO C; 1;RUA;2;LOTE 1;3;CENTRO;9;GASOLINA;22/09/2026;6,39;;R$ / litro;BRANCA")

    with caplog.at_level(logging.WARNING):
        resultado = list(raw.linhas_padronizadas(linhas, "a.csv"))

    assert len(resultado) == 3
    assert "1 linha(s) com número de colunas irregular" in caplog.text
