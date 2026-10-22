import io
import json
import re

import pytest
from botocore.exceptions import ClientError

import handler

RESUMO = {
    "periodo": {"inicio": "2026-10-02", "fim": "2026-10-17"},
    "gerado_em": "2026-10-21T09:12:44+00:00",
    "preco_medio_por_uf": [
        {
            "uf": "SP",
            "produto": "GASOLINA",
            "unidade": "R$ / litro",
            "preco_medio": 6.412,
            "preco_min": 5.99,
            "preco_max": 7.29,
            "coletas": 1200,
        },
        {
            "uf": "SP",
            "produto": "ETANOL",
            "unidade": "R$ / litro",
            "preco_medio": 3.9,
            "preco_min": 3.5,
            "preco_max": 4.5,
            "coletas": 900,
        },
    ],
    "etanol_vs_gasolina": {
        "municipios_analisados": 2,
        "municipios_onde_etanol_compensa": 1,
        "melhores_para_etanol": [],
    },
}


class S3Falso:
    def __init__(self, objetos):
        self.objetos = objetos
        self.chaves_lidas = []

    def get_object(self, Bucket, Key):
        self.chaves_lidas.append(Key)
        if Key not in self.objetos:
            raise ClientError({"Error": {"Code": "NoSuchKey"}}, "GetObject")
        return {"Body": io.BytesIO(json.dumps(self.objetos[Key]).encode())}


@pytest.fixture
def s3(monkeypatch):
    falso = S3Falso({"resultados/latest.json": RESUMO, "resultados/2026-10-17.json": RESUMO})
    monkeypatch.setattr(handler, "s3", falso)
    monkeypatch.setenv("BUCKET_NAME", "bucket")
    return falso


def evento(params=None, metodo="GET", path="/"):
    return {"rawPath": path, "queryStringParameters": params, "requestContext": {"http": {"method": metodo}}}


def test_home_e_o_mapa(s3):
    resposta = handler.lambda_handler(evento(), None)
    assert resposta["statusCode"] == 200
    assert resposta["headers"]["Content-Type"].startswith("text/html")
    assert s3.chaves_lidas == ["resultados/latest.json"]


def test_json_devolve_latest_com_cache_e_cors(s3):
    resposta = handler.lambda_handler(evento({"formato": "json"}), None)
    assert resposta["statusCode"] == 200
    assert json.loads(resposta["body"])["periodo"]["fim"] == "2026-10-17"
    assert resposta["headers"]["Cache-Control"] == "max-age=300"
    assert resposta["headers"]["Access-Control-Allow-Origin"] == "*"
    assert s3.chaves_lidas == ["resultados/latest.json"]


def test_periodo_existente(s3):
    resposta = handler.lambda_handler(evento({"periodo": "2026-10-17", "formato": "json"}), None)
    assert resposta["statusCode"] == 200
    assert json.loads(resposta["body"])["periodo"]["fim"] == "2026-10-17"
    assert s3.chaves_lidas == ["resultados/2026-10-17.json"]


def test_periodo_sem_formato_devolve_o_mapa_desse_periodo(s3):
    resposta = handler.lambda_handler(evento({"periodo": "2026-10-17"}), None)
    assert resposta["headers"]["Content-Type"].startswith("text/html")
    assert s3.chaves_lidas == ["resultados/2026-10-17.json"]


def test_erros_na_home_sao_pagina_html(s3):
    s3.objetos.clear()
    resposta = handler.lambda_handler(evento(), None)
    assert resposta["statusCode"] == 404
    assert resposta["headers"]["Content-Type"].startswith("text/html")
    assert "Nenhum período publicado" in resposta["body"]

    resposta = handler.lambda_handler(evento({"periodo": "<b>"}), None)
    assert resposta["statusCode"] == 400
    assert resposta["headers"]["Content-Type"].startswith("text/html")
    assert "<b>" not in resposta["body"].split("<body>")[1]


def test_erros_em_json_continuam_json(s3):
    resposta = handler.lambda_handler(evento({"periodo": "2020-01-01", "formato": "json"}), None)
    assert resposta["statusCode"] == 404
    assert json.loads(resposta["body"]) == {"erro": "Período não encontrado: 2020-01-01"}


@pytest.mark.parametrize("periodo", ["17/10/2026", "2026-13-01", "../latest", "2026-10-17.json"])
def test_periodo_invalido_da_400_sem_tocar_no_s3(s3, periodo):
    resposta = handler.lambda_handler(evento({"periodo": periodo}), None)
    assert resposta["statusCode"] == 400
    assert s3.chaves_lidas == []


def test_periodo_inexistente_da_404(s3):
    assert handler.lambda_handler(evento({"periodo": "2020-01-01"}), None)["statusCode"] == 404


def _dados_da_pagina(corpo: str) -> dict:
    inicio = corpo.index('<script id="dados" type="application/json">') + len(
        '<script id="dados" type="application/json">'
    )
    return json.loads(corpo[inicio : corpo.index("</script>", inicio)])


def test_html_e_o_mapa_com_os_dados_do_periodo(s3):
    resposta = handler.lambda_handler(evento({"formato": "html"}), None)
    assert resposta["statusCode"] == 200
    assert resposta["headers"]["Content-Type"].startswith("text/html")
    dados = _dados_da_pagina(resposta["body"])
    assert len(dados["mapa"]["ufs"]) == 27
    assert set(dados["mapa"]["ufs"]) == set(dados["nomes"])
    assert {(l["uf"], l["produto"], l["preco_medio"]) for l in dados["precos"]} == {
        ("SP", "GASOLINA", 6.412),
        ("SP", "ETANOL", 3.9),
    }
    assert dados["periodo"] == RESUMO["periodo"]


def test_html_nao_deixa_dado_fechar_o_script(s3):
    s3.objetos["resultados/latest.json"] = {
        **RESUMO,
        "preco_medio_por_uf": [{**RESUMO["preco_medio_por_uf"][0], "uf": "</script><b>x"}],
    }
    corpo = handler.lambda_handler(evento({"formato": "html"}), None)["body"]
    assert "</script><b>" not in corpo
    assert _dados_da_pagina(corpo)["precos"][0]["uf"] == "</script><b>x"


def test_outras_rotas_e_metodos(s3):
    assert handler.lambda_handler(evento(path="/favicon.ico"), None)["statusCode"] == 404
    assert handler.lambda_handler(evento(metodo="POST"), None)["statusCode"] == 405
    assert handler.lambda_handler(evento({"formato": "xml"}), None)["statusCode"] == 400


def test_access_denied_da_404(monkeypatch):
    # Na AWS, sem ListBucket, objeto inexistente chega como AccessDenied.
    class S3Negado:
        def get_object(self, Bucket, Key):
            raise ClientError({"Error": {"Code": "AccessDenied"}}, "GetObject")

    monkeypatch.setattr(handler, "s3", S3Negado())
    monkeypatch.setenv("BUCKET_NAME", "bucket")
    assert handler.lambda_handler(evento({"periodo": "2020-01-01"}), None)["statusCode"] == 404


def test_pagina_respeita_a_csp_do_site(s3):
    # A CloudFront aplica script-src 'self' e style-src 'self': nada inline,
    # exceto o bloco de dados (application/json não é executado).
    corpo = handler.lambda_handler(evento(), None)["body"]
    assert "<style" not in corpo
    scripts = re.findall(r"<script([^>]*)>", corpo)
    assert all("src=" in attrs or 'type="application/json"' in attrs for attrs in scripts)
    marcacao = re.sub(r"<script.*?</script>", "", corpo, flags=re.S)
    assert ' style="' not in marcacao and not re.search(r"\son[a-z]+=", marcacao)


def test_estaticos_com_versao(s3):
    corpo = handler.lambda_handler(evento(), None)["body"]
    assert f'href="/estilo.css?v={handler.VERSAO["/estilo.css"]}"' in corpo
    assert f'src="/mapa.js?v={handler.VERSAO["/mapa.js"]}"' in corpo
    css = handler.lambda_handler(evento(path="/estilo.css"), None)
    js = handler.lambda_handler(evento(path="/mapa.js"), None)
    assert css["headers"]["Content-Type"].startswith("text/css")
    assert js["headers"]["Content-Type"].startswith("text/javascript")
    assert "contorno" in js["body"]
    assert s3.chaves_lidas == ["resultados/latest.json"]


@pytest.mark.parametrize("path", ["/gasolina", "/gasolina/"])
def test_prefixo_da_cloudfront(s3, monkeypatch, path):
    monkeypatch.setenv("BASE_PATH", "/gasolina")
    resposta = handler.lambda_handler(evento(path=path), None)
    assert resposta["statusCode"] == 200
    assert 'href="/gasolina/estilo.css?v=' in resposta["body"]
    assert handler.lambda_handler(evento(path="/gasolina/mapa.js"), None)["statusCode"] == 200


def test_prefixo_recusa_outros_caminhos(s3, monkeypatch):
    monkeypatch.setenv("BASE_PATH", "/gasolina")
    for path in ["/", "/gasolinax", "/huberclaude", "/gasolina/nada"]:
        assert handler.lambda_handler(evento(path=path), None)["statusCode"] == 404, path


def test_link_da_pagina_de_erro_usa_o_prefixo(s3, monkeypatch):
    monkeypatch.setenv("BASE_PATH", "/gasolina")
    corpo = handler.lambda_handler(evento({"periodo": "2020-01-01"}, path="/gasolina"), None)["body"]
    assert 'href="/gasolina/"' in corpo


def test_head_sem_corpo(s3):
    resposta = handler.lambda_handler(evento(metodo="HEAD"), None)
    assert resposta["statusCode"] == 200 and resposta["body"] == ""
