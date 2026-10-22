FROM apache/airflow:3.3.2-python3.12

# As constraints da versão impedem que uma dependência extra troque pacotes
# de que o Airflow depende.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-3.3.2/constraints-3.12.txt"

# dbt em venv próprio para não conflitar com as constraints do Airflow.
USER root
RUN python -m venv /opt/dbt \
    && /opt/dbt/bin/pip install --no-cache-dir dbt-core==1.12.6 dbt-postgres==1.11.0
USER airflow
