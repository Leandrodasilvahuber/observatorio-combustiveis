-- Uma linha por UF e produto: duas unidades de medida para o mesmo produto
-- duplicariam o estado no ranking da página.
select uf, produto, count(*) as linhas
from {{ ref('agg_uf_periodo') }}
group by uf, produto
having count(*) > 1
