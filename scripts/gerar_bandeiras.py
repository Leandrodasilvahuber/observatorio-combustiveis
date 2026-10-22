"""Gera api/bandeiras.png: as bandeiras das 27 UFs lado a lado, em ordem
alfabética da sigla, para a tabela de ranking da home.

Baixa as miniaturas do Wikimedia Commons e redimensiona cada uma para
LARGURA x ALTURA (em 2x, para telas de alta densidade). Só precisa rodar de
novo se mudar alguma bandeira ou o tamanho.

    python scripts/gerar_bandeiras.py [saida.png]
"""

import io
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

SAIDA_PADRAO = Path(__file__).resolve().parent.parent / "api" / "bandeiras.png"
LARGURA, ALTURA = 21, 15  # tamanho exibido; a imagem tem o dobro
URL = "https://commons.wikimedia.org/wiki/Special:FilePath/{}?width=120"

# fmt: off
ARQUIVOS = {
    "AC": "Flag of Acre.svg", "AL": "Flag of Alagoas.svg", "AM": "Flag of Amazonas.svg",
    "AP": "Flag of Amapá.svg", "BA": "Flag of Bahia.svg", "CE": "Flag of Ceará.svg",
    "DF": "Bandeira do Distrito Federal (Brasil).svg", "ES": "Flag of Espírito Santo.svg",
    "GO": "Flag of Goiás.svg", "MA": "Flag of Maranhão.svg", "MG": "Flag of Minas Gerais.svg",
    "MS": "Flag of Mato Grosso do Sul.svg", "MT": "Flag of Mato Grosso.svg", "PA": "Flag of Pará.svg",
    "PB": "Flag of Paraíba.svg", "PE": "Flag of Pernambuco.svg", "PI": "Flag of Piauí.svg",
    "PR": "Flag of Paraná.svg", "RJ": "Flag of Rio de Janeiro.svg", "RN": "Flag of Rio Grande do Norte.svg",
    "RO": "Flag of Rondônia.svg", "RR": "Flag of Roraima.svg", "RS": "Flag of Rio Grande do Sul.svg",
    "SC": "Flag of Santa Catarina.svg", "SE": "Flag of Sergipe.svg", "SP": "Bandeira do estado de São Paulo.svg",
    "TO": "Flag of Tocantins.svg",
}
# fmt: on


def baixar(arquivo: str) -> Image.Image:
    url = URL.format(urllib.parse.quote(arquivo.replace(" ", "_")))
    pedido = urllib.request.Request(url, headers={"User-Agent": "observatorio-combustiveis/1.0"})  # noqa: S310
    with urllib.request.urlopen(pedido, timeout=60) as resposta:  # noqa: S310 (URL constante, https)
        return Image.open(io.BytesIO(resposta.read())).convert("RGBA")


def main() -> None:
    saida = Path(sys.argv[1]) if len(sys.argv) > 1 else SAIDA_PADRAO
    w, h = LARGURA * 2, ALTURA * 2
    sprite = Image.new("RGBA", (w * len(ARQUIVOS), h))
    for i, uf in enumerate(sorted(ARQUIVOS)):
        sprite.paste(baixar(ARQUIVOS[uf]).resize((w, h), Image.LANCZOS), (i * w, 0))
    sprite.save(saida, optimize=True)
    print(f"{saida}: {len(ARQUIVOS)} bandeiras, {saida.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
