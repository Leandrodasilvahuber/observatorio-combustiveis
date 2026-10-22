"""Gera api/mapa_brasil.json: contornos das UFs em caminhos SVG.

Baixa a malha de estados do IBGE (qualidade mínima), projeta em
equiretangular com escala cos(15°) (o centro aproximado do país) e simplifica
com Douglas-Peucker. Só precisa rodar de novo se mudar a malha ou o nível de
simplificação.

    python scripts/gerar_mapa.py [saida.json]
"""

import gzip
import json
import math
import sys
import urllib.request
from pathlib import Path

URL_MALHA = (
    "https://servicodados.ibge.gov.br/api/v3/malhas/paises/BR"
    "?formato=application/vnd.geo%2Bjson&intrarregiao=UF&qualidade=minima"
)
SAIDA_PADRAO = Path(__file__).resolve().parent.parent / "api" / "mapa_brasil.json"
LARGURA = 600
TOLERANCIA = 0.6  # em unidades do viewBox

# Código IBGE da UF -> sigla
# fmt: off
UF_POR_CODIGO = {
    "11": "RO", "12": "AC", "13": "AM", "14": "RR", "15": "PA", "16": "AP", "17": "TO",
    "21": "MA", "22": "PI", "23": "CE", "24": "RN", "25": "PB", "26": "PE", "27": "AL",
    "28": "SE", "29": "BA", "31": "MG", "32": "ES", "33": "RJ", "35": "SP", "41": "PR",
    "42": "SC", "43": "RS", "50": "MS", "51": "MT", "52": "GO", "53": "DF",
}
# fmt: on


def simplificar(pontos: list, tolerancia: float) -> list:
    """Douglas-Peucker: mantém os pontos que se afastam mais que a tolerância."""
    if len(pontos) < 3:
        return pontos
    (x1, y1), (x2, y2) = pontos[0], pontos[-1]
    dx, dy = x2 - x1, y2 - y1
    norma = math.hypot(dx, dy)
    indice, maior = 0, 0.0
    for i in range(1, len(pontos) - 1):
        x, y = pontos[i]
        d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / norma if norma else math.hypot(x - x1, y - y1)
        if d > maior:
            indice, maior = i, d
    if maior <= tolerancia:
        return [pontos[0], pontos[-1]]
    return simplificar(pontos[: indice + 1], tolerancia)[:-1] + simplificar(pontos[indice:], tolerancia)


def _poligonos(geometria: dict) -> list:
    if geometria["type"] == "Polygon":
        return [geometria["coordinates"]]
    return geometria["coordinates"]


def gerar(malha: dict) -> dict:
    k = math.cos(math.radians(15))
    coords = [
        ponto
        for f in malha["features"]
        for poligono in _poligonos(f["geometry"])
        for anel in poligono
        for ponto in anel
    ]
    lon_min = min(lon for lon, _ in coords)
    lon_max = max(lon for lon, _ in coords)
    lat_min = min(lat for _, lat in coords)
    lat_max = max(lat for _, lat in coords)
    escala = LARGURA / ((lon_max - lon_min) * k)

    ufs = {}
    for f in malha["features"]:
        partes = []
        for poligono in _poligonos(f["geometry"]):
            for anel in poligono:
                pontos = [((lon - lon_min) * k * escala, (lat_max - lat) * escala) for lon, lat in anel]
                pontos = simplificar(pontos, TOLERANCIA)
                if len(pontos) < 4:  # anel fechado reduzido a menos de um triângulo
                    continue
                partes.append("M" + "L".join(f"{x:.1f},{y:.1f}" for x, y in pontos[:-1]) + "Z")
        ufs[UF_POR_CODIGO[f["properties"]["codarea"]]] = "".join(partes)

    if len(ufs) != 27:
        raise ValueError(f"esperava 27 UFs na malha, vieram {len(ufs)}")
    return {"largura": LARGURA, "altura": round((lat_max - lat_min) * escala), "ufs": dict(sorted(ufs.items()))}


def main() -> None:
    saida = Path(sys.argv[1]) if len(sys.argv) > 1 else SAIDA_PADRAO
    with urllib.request.urlopen(URL_MALHA, timeout=60) as resposta:  # noqa: S310 (URL constante, https)
        corpo = resposta.read()
    # O IBGE devolve gzip mesmo sem Accept-Encoding.
    if corpo[:2] == b"\x1f\x8b":
        corpo = gzip.decompress(corpo)
    malha = json.loads(corpo)
    mapa = gerar(malha)
    saida.write_text(json.dumps(mapa, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{saida}: {len(mapa['ufs'])} UFs, {saida.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
