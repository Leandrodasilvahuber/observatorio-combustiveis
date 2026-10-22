"""DAG do Observatório de Combustíveis.

baixar_para_bronze -> validar -> carregar_raw -> dbt_build -> publicar_resultados.
Se qualquer task falhar, nada é publicado e a Lambda segue servindo o último
período válido.
"""

import os
from datetime import datetime, timedelta

from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.sdk import Variable, dag, task

from observatorio import bronze, config, publicar, raw

# Local o próprio Airflow agenda; na AWS quem marca o tempo é o EventBridge,
# que liga a EC2, e o script de boot dispara a DAG.
MODO_AGENDA = os.environ.get("OBS_MODO_AGENDA", "interno")
SCHEDULE = timedelta(days=10) if MODO_AGENDA == "interno" else None

DBT_DIR = "/opt/airflow/dbt"


@dag(
    dag_id="observatorio_combustiveis",
    schedule=SCHEDULE,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=10)},
    tags=["observatorio", "anp"],
    doc_md=__doc__,
)
def observatorio_combustiveis():
    @task
    def baixar_para_bronze(**context) -> list[str]:
        urls = Variable.get("anp_urls", default=None, deserialize_json=True) or config.ANP_URLS_PADRAO
        # Disparos manuais podem não ter logical_date no Airflow 3.
        momento = context.get("logical_date") or context["dag_run"].run_after
        return bronze.baixar_para_bronze(urls, momento.date())

    @task
    def validar(chaves: list[str]) -> list[str]:
        return bronze.validar(chaves)

    @task
    def carregar_raw(chaves: list[str]) -> dict[str, int]:
        conn = PostgresHook(postgres_conn_id=config.CONN_ID_DW).get_conn()
        try:
            return raw.carregar_raw(conn, chaves)
        finally:
            conn.close()

    @task.bash
    def dbt_build() -> str:
        # Modelos e testes juntos: um teste reprovado falha a task e nada
        # é publicado depois dela.
        return f"/opt/dbt/bin/dbt build --project-dir {DBT_DIR} --profiles-dir {DBT_DIR}"

    @task
    def publicar_resultados() -> list[str]:
        conn = PostgresHook(postgres_conn_id=config.CONN_ID_DW).get_conn()
        try:
            return publicar.publicar_resultados(conn)
        finally:
            conn.close()

    carregar_raw(validar(baixar_para_bronze())) >> dbt_build() >> publicar_resultados()


observatorio_combustiveis()
