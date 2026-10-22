-- Preço médio, mínimo, máximo e coletas por UF e produto, nos 10 dias mais
-- recentes com dados.

with periodo as (

    select
        max(data_coleta) - 9  as inicio,
        max(data_coleta)      as fim
    from {{ ref('fct_precos') }}

)

select
    p.inicio                         as periodo_inicio,
    p.fim                            as periodo_fim,
    f.uf,
    f.produto,
    f.unidade_medida,
    round(avg(f.valor_venda), 3)     as preco_medio,
    min(f.valor_venda)               as preco_min,
    max(f.valor_venda)               as preco_max,
    count(*)                         as coletas
from {{ ref('fct_precos') }} f
cross join periodo p
where f.data_coleta between p.inicio and p.fim
group by p.inicio, p.fim, f.uf, f.produto, f.unidade_medida
