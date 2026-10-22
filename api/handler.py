"""API de resultados (Lambda Function URL).

Só lê os JSON prontos em resultados/; nunca consulta o banco, que fica
desligado quase o tempo todo.

Na AWS fica atrás da CloudFront em /gasolina (BASE_PATH); localmente na raiz.

GET <base>                       home: mapa do Brasil com o ranking de preço por estado
GET <base>?formato=json          JSON do último período (resultados/latest.json)
GET <base>?periodo=AAAA-MM-DD    período que termina nessa data (mapa ou JSON)
GET <base>/estilo.css, mapa.js   arquivos da página (a CSP do site bloqueia inline)
"""

import hashlib
import html
import json
import os
import re
from datetime import date

import boto3
from botocore.exceptions import ClientError

PERIODO = re.compile(r"^\d{4}-\d{2}-\d{2}$")
CABECALHOS = {
    "Cache-Control": "max-age=300",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
}
HTML = "text/html; charset=utf-8"

s3 = boto3.client("s3")

_PASTA = os.path.dirname(__file__)


def _ler(nome: str) -> str:
    with open(os.path.join(_PASTA, nome), encoding="utf-8") as f:
        return f.read()


# Contornos das UFs em SVG, gerados por scripts/gerar_mapa.py a partir da malha
# de estados do IBGE.
MAPA = json.loads(_ler("mapa_brasil.json"))

# Página do mapa. Os dados entram no lugar de __DADOS__; o resto é estático.
PAGINA = _ler("pagina.html")

PAGINA_ERRO = """<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Combustíveis por estado</title>
<link rel="stylesheet" href="__ESTILO__">
</head><body><main class="erro"><h1>Preço dos combustíveis por estado</h1>
<p>__MENSAGEM__</p><p><a href="__HOME__">Ver o período mais recente</a></p></main></body></html>"""

# Arquivos servidos pela própria Lambda. O link leva um hash do conteúdo
# (?v=...), então um deploy novo não fica preso no cache da CloudFront.
ESTATICOS = {
    "/estilo.css": (_ler("estilo.css"), "text/css; charset=utf-8"),
    "/mapa.js": (_ler("mapa.js"), "text/javascript; charset=utf-8"),
}
VERSAO = {nome: hashlib.sha256(corpo.encode()).hexdigest()[:10] for nome, (corpo, _) in ESTATICOS.items()}

# fmt: off
NOMES_UF = {
    "AC": "Acre", "AL": "Alagoas", "AM": "Amazonas", "AP": "Amapá", "BA": "Bahia",
    "CE": "Ceará", "DF": "Distrito Federal", "ES": "Espírito Santo", "GO": "Goiás",
    "MA": "Maranhão", "MG": "Minas Gerais", "MS": "Mato Grosso do Sul", "MT": "Mato Grosso",
    "PA": "Pará", "PB": "Paraíba", "PE": "Pernambuco", "PI": "Piauí", "PR": "Paraná",
    "RJ": "Rio de Janeiro", "RN": "Rio Grande do Norte", "RO": "Rondônia", "RR": "Roraima",
    "RS": "Rio Grande do Sul", "SC": "Santa Catarina", "SE": "Sergipe", "SP": "São Paulo",
    "TO": "Tocantins",
}
# fmt: on


def _base() -> str:
    """Prefixo do site: "/gasolina" na AWS, "" localmente."""
    return os.environ.get("BASE_PATH", "").rstrip("/")


def _estatico(nome: str) -> str:
    return f"{_base()}{nome}?v={VERSAO[nome]}"


def _resposta(status: int, corpo, tipo="application/json; charset=utf-8") -> dict:
    if not isinstance(corpo, str):
        corpo = json.dumps(corpo, ensure_ascii=False)
    return {"statusCode": status, "headers": {**CABECALHOS, "Content-Type": tipo}, "body": corpo}


def _erro(status: int, mensagem: str, formato: str = "json") -> dict:
    if formato == "html":
        pagina = (
            PAGINA_ERRO.replace("__ESTILO__", _estatico("/estilo.css"))
            .replace("__HOME__", f"{_base()}/")
            .replace("__MENSAGEM__", html.escape(mensagem))
        )
        return _resposta(status, pagina, HTML)
    return _resposta(status, {"erro": mensagem})


def _periodo_valido(valor: str) -> bool:
    if not PERIODO.match(valor):
        return False
    try:
        date.fromisoformat(valor)
    except ValueError:
        return False
    return True


def _html(resumo: dict) -> str:
    """Mapa do Brasil por produto: cada UF colorida pela faixa do ranking de
    preço médio, com os números ao passar o mouse e uma tabela de ranking."""
    dados = {
        "periodo": resumo["periodo"],
        "precos": resumo["preco_medio_por_uf"],
        "etanol": {k: v for k, v in resumo["etanol_vs_gasolina"].items() if k != "melhores_para_etanol"},
        "mapa": MAPA,
        "nomes": NOMES_UF,
    }
    # "<" escapado para o JSON não fechar a tag <script> antes da hora.
    json_dados = json.dumps(dados, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    return (
        PAGINA.replace("__ESTILO__", _estatico("/estilo.css"))
        .replace("__SCRIPT__", _estatico("/mapa.js"))
        .replace("__DADOS__", json_dados)
    )


def _rota(caminho: str) -> str | None:
    """Caminho relativo ao prefixo ("/" para a home) ou None se for de fora."""
    base = _base()
    if base:
        if caminho != base and not caminho.startswith(base + "/"):
            return None
        caminho = caminho[len(base) :]
    return caminho or "/"


def lambda_handler(event, context):
    http = event.get("requestContext", {}).get("http", {})
    metodo = http.get("method", "GET")
    if metodo == "OPTIONS":
        return {"statusCode": 204, "headers": CABECALHOS, "body": ""}
    if metodo not in ("GET", "HEAD"):
        return _erro(405, "Use GET")
    resposta = _get(event)
    if metodo == "HEAD":
        resposta["body"] = ""
    return resposta


def _get(event) -> dict:
    rota = _rota(event.get("rawPath", "/"))
    if rota in ESTATICOS:
        corpo, tipo = ESTATICOS[rota]
        return _resposta(200, corpo, tipo)
    if rota != "/":
        return _erro(404, "Rota não encontrada")

    params = event.get("queryStringParameters") or {}
    formato = params.get("formato", "html")
    if formato not in ("json", "html"):
        return _erro(400, "formato deve ser json ou html")

    periodo = params.get("periodo")
    if periodo is not None and not _periodo_valido(periodo):
        return _erro(400, "periodo deve estar no formato AAAA-MM-DD", formato)

    prefixo = os.environ.get("PREFIXO_RESULTADOS", "resultados")
    chave = f"{prefixo}/{periodo or 'latest'}.json"
    try:
        objeto = s3.get_object(Bucket=os.environ["BUCKET_NAME"], Key=chave)
    except ClientError as e:
        # Na AWS, objeto inexistente vira AccessDenied quando a role não tem
        # ListBucket irrestrito; nos dois casos o período não existe para a API.
        if e.response["Error"]["Code"] in ("NoSuchKey", "404", "AccessDenied", "403"):
            if periodo is None:
                return _erro(
                    404, "Nenhum período publicado ainda: o primeiro ciclo do pipeline ainda não terminou.", formato
                )
            return _erro(404, f"Período não encontrado: {periodo}", formato)
        raise

    conteudo = objeto["Body"].read().decode()
    if formato == "html":
        return _resposta(200, _html(json.loads(conteudo)), HTML)
    return _resposta(200, conteudo)
