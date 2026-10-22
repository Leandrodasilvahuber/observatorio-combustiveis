-- Uma linha por posto, produto e dia.
select cnpj, produto, data_coleta, count(*) as linhas
from {{ ref('fct_precos') }}
group by cnpj, produto, data_coleta
having count(*) > 1
