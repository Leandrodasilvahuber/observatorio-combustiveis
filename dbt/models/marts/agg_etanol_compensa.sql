-- Municípios com coletas de gasolina comum e etanol no período (10 dias mais
-- recentes desses dois produtos). Regra prática: etanol compensa se custar até
-- 70% da gasolina. É uma aproximação; o rendimento real varia por veículo.

with periodo as (

    -- Só gasolina e etanol: o arquivo de diesel/GNV mais novo não encurta a janela.
    select
        max(data_coleta) - 9  as inicio,
        max(data_coleta)      as fim
    from {{ ref('fct_precos') }}
    where produto in ('GASOLINA', 'ETANOL')

),

medias as (

    select
        p.inicio,
        p.fim,
        f.uf,
        f.municipio,
        avg(f.valor_venda) filter (where f.produto = 'GASOLINA') as gasolina,
        avg(f.valor_venda) filter (where f.produto = 'ETANOL')   as etanol
    from {{ ref('fct_precos') }} f
    cross join periodo p
    where f.data_coleta between p.inicio and p.fim
      and f.produto in ('GASOLINA', 'ETANOL')
    group by p.inicio, p.fim, f.uf, f.municipio

)

select
    inicio                          as periodo_inicio,
    fim                             as periodo_fim,
    uf,
    municipio,
    round(gasolina, 3)              as preco_medio_gasolina,
    round(etanol, 3)                as preco_medio_etanol,
    round(etanol / gasolina, 3)     as razao,
    etanol / gasolina <= 0.70       as etanol_compensa
from medias
where gasolina is not null
  and etanol is not null
