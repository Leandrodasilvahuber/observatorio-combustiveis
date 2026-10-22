-- Tipos convertidos, limpeza e deduplicação. Sem regra de negócio.
-- Cada execução baixa 4 semanas, então a mesma coleta aparece em arquivos
-- diferentes; fica a versão carregada mais recentemente.

with origem as (

    select
        upper(nullif(trim(regiao), ''))                          as regiao,
        upper(nullif(trim(uf), ''))                              as uf,
        upper(nullif(trim(municipio), ''))                       as municipio,
        nullif(trim(revenda), '')                                as revenda,
        nullif(regexp_replace(cnpj, '\D', '', 'g'), '')          as cnpj,
        upper(nullif(trim(produto), ''))                         as produto,
        -- Valores fora do formato viram nulos (e reprovam o not_null) em vez
        -- de derrubar a view com erro de conversão.
        case when trim(data_coleta) ~ '^\d{2}/\d{2}/\d{4}$'
             then to_date(trim(data_coleta), 'DD/MM/YYYY') end   as data_coleta,
        case when trim(valor_venda) ~ '^\d+(,\d+)?$'
             then replace(trim(valor_venda), ',', '.')::numeric(10, 3) end as valor_venda,
        nullif(trim(unidade_medida), '')                         as unidade_medida,
        coalesce(upper(nullif(trim(bandeira), '')), 'SEM BANDEIRA') as bandeira,
        arquivo_origem,
        carregado_em
    from {{ source('raw', 'precos_anp') }}

),

numerado as (

    select
        *,
        row_number() over (
            partition by cnpj, produto, data_coleta
            order by carregado_em desc, arquivo_origem desc, valor_venda desc
        ) as ordem
    from origem

)

select
    regiao,
    uf,
    municipio,
    revenda,
    cnpj,
    produto,
    data_coleta,
    valor_venda,
    unidade_medida,
    bandeira,
    arquivo_origem,
    carregado_em
from numerado
where ordem = 1
