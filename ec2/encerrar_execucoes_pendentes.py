"""Marca como failed as execuções da DAG que ficaram em queued/running.

Roda dentro do contêiner do Airflow (via stdin) antes de cada disparo. Uma
execução interrompida pelo desligamento da EC2 continuaria "running" no banco
e, com max_active_runs=1, seguraria o novo disparo na fila.

Uso: python - <dag_id> < encerrar_execucoes_pendentes.py
"""

import sys

from airflow.models import DagRun, TaskInstance
from airflow.utils.session import create_session
from airflow.utils.state import DagRunState, TaskInstanceState

dag_id = sys.argv[1]
pendentes = [DagRunState.QUEUED, DagRunState.RUNNING]

with create_session() as session:
    execucoes = session.query(DagRun).filter(DagRun.dag_id == dag_id, DagRun.state.in_(pendentes)).all()
    for execucao in execucoes:
        tarefas = session.query(TaskInstance).filter(
            TaskInstance.dag_id == dag_id,
            TaskInstance.run_id == execucao.run_id,
        )
        for tarefa in tarefas:
            if tarefa.state not in (TaskInstanceState.SUCCESS, TaskInstanceState.SKIPPED):
                tarefa.state = TaskInstanceState.FAILED
        execucao.state = DagRunState.FAILED
        print(f"execução pendente encerrada: {execucao.run_id}")

print(f"{len(execucoes)} execução(ões) pendente(s) encerrada(s)")
