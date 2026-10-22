from datetime import date, datetime, timezone
from decimal import Decimal

import pytest

from observatorio.publicar import montar_resumo

UF = [
    {
        "periodo_inicio": date(2026, 10, 2),
        "periodo_fim": date(2026, 10, 17),
        "uf": "SP",
        "produto": "GASOLINA",
        "unidade_medida": "R$ / litro",
        "preco_medio": Decimal("6.412"),
        "preco_min": Decimal("5.990"),
        "preco_max": Decimal("7.290"),
        "coletas": 1200,
    },
]
ETANOL = [
    {
        "uf": "SP",
        "municipio": "LINS",
        "preco_medio_gasolina": Decimal("6.511"),
        "preco_medio_etanol": Decimal("3.528"),
        "razao": Decimal("0.542"),
        "etanol_compensa": True,
    },
    {
        "uf": "RS",
        "municipio": "CANOAS",
        "preco_medio_gasolina": Decimal("6.390"),
        "preco_medio_etanol": Decimal("5.100"),
        "razao": Decimal("0.798"),
        "etanol_compensa": False,
    },
]


def test_resumo_segue_o_formato_documentado():
    resumo = montar_resumo(UF, ETANOL, datetime(2026, 10, 21, 9, 12, 44, tzinfo=timezone.utc))

    assert resumo["periodo"] == {"inicio": "2026-10-02", "fim": "2026-10-17", "dias": 16}
    assert resumo["gerado_em"] == "2026-10-21T09:12:44+00:00"
    assert resumo["preco_medio_por_uf"][0]["preco_medio"] == 6.412
    etanol = resumo["etanol_vs_gasolina"]
    assert etanol["municipios_analisados"] == 2
    assert etanol["municipios_onde_etanol_compensa"] == 1
    assert etanol["melhores_para_etanol"][0]["municipio"] == "LINS"


def test_sem_agregados_nao_publica():
    with pytest.raises(ValueError):
        montar_resumo([], ETANOL, datetime.now(timezone.utc))
