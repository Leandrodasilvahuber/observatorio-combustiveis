-- "R$/litro" e "R$ / litro" viram a mesma unidade (ela entra na chave do
-- agg_uf_periodo). Usada na staging e no pre_hook do fct_precos.
{% macro normalizar_unidade(coluna) -%}
    nullif(regexp_replace(regexp_replace(trim({{ coluna }}), '\s+', ' ', 'g'), ' ?/ ?', ' / ', 'g'), '')
{%- endmacro %}
