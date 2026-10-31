-- Preço médio, mínimo, máximo e coletas por UF e produto, nos 10 dias mais
-- recentes com dados de cada produto. A janela é por produto porque os dois
-- arquivos da ANP (gasolina/etanol e diesel/GNV) podem chegar com datas
-- diferentes; com uma janela única, o arquivo atrasado entraria com poucos dias.

with periodo as (

    select
        produto,
        max(data_coleta) - 9  as inicio,
        max(data_coleta)      as fim
    from {{ ref('fct_precos') }}
    group by produto

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
join periodo p on p.produto = f.produto
where f.data_coleta between p.inicio and p.fim
group by p.inicio, p.fim, f.uf, f.produto, f.unidade_medida
