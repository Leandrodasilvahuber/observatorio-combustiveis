-- Camada raw: valores exatamente como vieram da ANP, todos como texto.
-- Conversões, limpeza e deduplicação ficam na staging (dbt).
create schema if not exists raw;

create table if not exists raw.precos_anp (
    regiao          text,
    uf              text,
    municipio       text,
    revenda         text,
    cnpj            text,
    nome_rua        text,
    numero_rua      text,
    complemento     text,
    bairro          text,
    cep             text,
    produto         text,
    data_coleta     text,
    valor_venda     text,
    valor_compra    text,
    unidade_medida  text,
    bandeira        text,
    arquivo_origem  text        not null,
    carregado_em    timestamptz not null default now()
);

create index if not exists precos_anp_arquivo_origem_idx
    on raw.precos_anp (arquivo_origem);
