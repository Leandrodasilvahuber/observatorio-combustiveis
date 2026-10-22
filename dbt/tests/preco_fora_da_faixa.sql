-- Preços fora de (0, 20] indicam erro de digitação ou de conversão.
-- Testa a staging (e não o fato) para que o dbt build pare antes de o
-- fct_precos incremental receber a linha ruim.
select cnpj, produto, data_coleta, valor_venda, arquivo_origem
from {{ ref('stg_precos') }}
where valor_venda <= 0 or valor_venda > 20
