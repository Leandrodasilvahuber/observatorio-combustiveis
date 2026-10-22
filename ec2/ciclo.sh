#!/usr/bin/env bash
# Ciclo da EC2: sobe Postgres e Airflow, dispara a DAG, espera terminar,
# envia os logs ao S3 e desliga a máquina.
#
# Modo manutenção (a máquina não roda a DAG e não desliga):
#   - arquivo $ESTADO_DIR/MANUTENCAO na instância, ou
#   - objeto s3://$OBS_BUCKET/config/MANUTENCAO (dá para ativar com a EC2 desligada)
#
# Os padrões abaixo valem para a EC2; os testes locais sobrescrevem por env.
set -euo pipefail

ESTADO_DIR="${ESTADO_DIR:-/opt/observatorio}"
APP_DIR="${APP_DIR:-$ESTADO_DIR/app}"
export COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.aws.yml}"
DESLIGAR="${DESLIGAR:-shutdown -h now}"
TIMEOUT_DAG_S="${TIMEOUT_DAG_S:-10800}"
DAG_ID=observatorio_combustiveis
INICIO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_ID=""

mkdir -p "$ESTADO_DIR/logs"
LOG="$ESTADO_DIR/logs/ciclo-$INICIO.log"
exec >>"$LOG" 2>&1

set -a
# shellcheck source=/dev/null
source "$ESTADO_DIR/.env"
set +a

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
compose() { docker compose --env-file "$ESTADO_DIR/.env" "$@"; }

em_manutencao() {
    [[ -f "$ESTADO_DIR/MANUTENCAO" ]] && return 0
    aws s3api head-object --bucket "$OBS_BUCKET" --key config/MANUTENCAO >/dev/null 2>&1
}

# shellcheck disable=SC2329  # chamada por finalizar (trap EXIT)
enviar_logs() {
    if [[ -n "$RUN_ID" ]]; then
        compose exec -T airflow tar -C /opt/airflow/logs -cz "dag_id=$DAG_ID/run_id=$RUN_ID" \
            | aws s3 cp - "s3://$OBS_BUCKET/logs/airflow-$INICIO.tar.gz" --only-show-errors \
            || log "não foi possível enviar os logs do Airflow"
    fi
    aws s3 cp "$LOG" "s3://$OBS_BUCKET/logs/$(basename "$LOG")" --only-show-errors \
        || echo "não foi possível enviar $LOG"
}

# shellcheck disable=SC2329  # chamada pelo trap EXIT
finalizar() {
    local status=$?
    log "ciclo terminou com status $status"
    if [[ $status -ne 0 ]]; then
        compose logs --tail 100 airflow 2>/dev/null || true
    fi
    enviar_logs
    if em_manutencao; then
        log "modo manutenção ativo: a máquina continua ligada"
        return
    fi
    compose stop || true
    $DESLIGAR
}

if em_manutencao; then
    log "modo manutenção ativo: ciclo não executado e a máquina continua ligada"
    exit 0
fi

trap finalizar EXIT
# Garante o EXIT trap mesmo se o systemd encerrar o serviço por timeout.
trap 'exit 143' TERM

cd "$APP_DIR"
log "subindo contêineres"
if ! compose up -d --build --wait; then
    log "falha ao subir; nova tentativa em 60s"
    sleep 60
    compose up -d --build --wait
fi

log "aguardando a DAG ser registrada"
for _ in $(seq 60); do
    if compose exec -T airflow airflow dags list -o plain 2>/dev/null | grep -qw "$DAG_ID"; then
        break
    fi
    sleep 5
done

# Execuções interrompidas por um desligamento anterior seguram a fila
# (max_active_runs=1); são encerradas antes do novo disparo.
compose exec -T airflow python - "$DAG_ID" < ec2/encerrar_execucoes_pendentes.py

RUN_ID="ec2__$INICIO"
log "disparando $DAG_ID ($RUN_ID)"
compose exec -T airflow airflow dags unpause "$DAG_ID" >/dev/null
compose exec -T airflow airflow dags trigger "$DAG_ID" --run-id "$RUN_ID" >/dev/null

limite=$((SECONDS + TIMEOUT_DAG_S))
estado=""
while (( SECONDS < limite )); do
    estado="$(compose exec -T airflow airflow dags list-runs "$DAG_ID" -o json 2>/dev/null \
        | python3 -c 'import json, sys
runs = [r for r in json.load(sys.stdin) if r["run_id"] == sys.argv[1]]
print(runs[0]["state"] if runs else "")' "$RUN_ID" || true)"
    case "$estado" in
        success) log "DAG concluída com sucesso"; exit 0 ;;
        failed)  log "DAG falhou"; exit 1 ;;
    esac
    sleep 30
done

log "DAG não terminou em ${TIMEOUT_DAG_S}s (último estado: ${estado:-desconhecido})"
exit 1
