-- Um preço de venda por posto, produto e dia de coleta.
-- Incremental: reprocessa os últimos 35 dias e faz upsert pela chave.
-- O pre_hook normaliza a unidade das linhas fora dessa janela: um
-- --full-refresh não serve, porque a raw só guarda 45 dias (raw.RETENCAO_DIAS)
-- e o histórico anterior se perderia.

{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['cnpj', 'produto', 'data_coleta'],
        pre_hook="{% if is_incremental() %}"
                 "update {{ this }} set unidade_medida = {{ normalizar_unidade('unidade_medida') }} "
                 "where unidade_medida is distinct from {{ normalizar_unidade('unidade_medida') }}"
                 "{% endif %}",
    )
}}

select
    cnpj,
    produto,
    data_coleta,
    uf,
    regiao,
    municipio,
    revenda,
    bandeira,
    valor_venda,
    unidade_medida
from {{ ref('stg_precos') }}

{% if is_incremental() %}
-- coalesce: com a tabela existente mas vazia, max() seria nulo e o filtro
-- não deixaria passar nenhuma linha.
where data_coleta >= (select coalesce(max(data_coleta) - 35, date '1900-01-01') from {{ this }})
{% endif %}
