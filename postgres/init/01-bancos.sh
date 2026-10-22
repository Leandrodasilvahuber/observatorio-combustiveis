#!/bin/bash
# Executado só na primeira inicialização do volume. Cria o banco de metadados
# do Airflow; o banco do projeto (POSTGRES_DB) já é criado pela imagem.
set -euo pipefail

# A senha entra como variável do psql (:'senha'), que faz o escape de aspas.
psql -v ON_ERROR_STOP=1 -v senha="$AIRFLOW_DB_PASSWORD" \
    --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'EOSQL'
    CREATE USER airflow WITH PASSWORD :'senha';
    CREATE DATABASE airflow OWNER airflow;
EOSQL
