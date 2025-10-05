#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/.env"

log_section() { echo; echo "==> $1"; }
abort() { echo "Error: $1" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || abort "Docker is required to start the project."

[[ -f "${COMPOSE_FILE}" ]] || abort "docker-compose.yml not found at ${COMPOSE_FILE}"

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  abort "Neither 'docker compose' nor 'docker-compose' is available."
fi

compose() { "${COMPOSE_CMD[@]}" -f "${COMPOSE_FILE}" "$@"; }

cleanup() {
  log_section "Stopping containers (Ctrl-C detected)"
  compose down
}
trap cleanup INT

wait_for_service() {
  local service="$1" timeout="${2:-180}" interval="${3:-5}" elapsed=0
  while (( elapsed < timeout )); do
    if compose ps --status running --services | grep -qw "${service}"; then
      echo "  ✔ ${service} is running"; return 0
    fi
    if compose ps --status exited --services | grep -qw "${service}"; then
      echo "  ✖ ${service} exited early (check logs with: ${COMPOSE_CMD[*]} logs ${service})"; return 1
    fi
    sleep "${interval}"; elapsed=$((elapsed + interval))
  done
  echo "  ✖ ${service} did not reach running state within ${timeout}s"; return 1
}

get_host_port() {
  local service="$1" internal_port="$2" mapping
  if ! mapping=$(compose port "${service}" "${internal_port}" 2>/dev/null); then return 1; fi
  echo "${mapping##*:}"
}

log_section "Smart Transport Ticketing :: bootstrap"
echo "Project root : ${PROJECT_ROOT}"
echo "Compose file : ${COMPOSE_FILE}"
if [[ -f "${ENV_FILE}" ]]; then
  echo "Environment  : ${ENV_FILE}"
elif [[ -f "${PROJECT_ROOT}/.env.sample" ]]; then
  echo "Environment  : (none found – consider copying .env.sample → .env)"
else
  echo "Environment  : (none found – compose defaults will be used)"
fi

declare -a SERVICES_TO_WAIT=( "zookeeper" "kafka" "mongodb" "passenger-service" "transport-service" )

log_section "Building and starting containers"
compose up -d --build

log_section "Waiting for core services"
for s in "${SERVICES_TO_WAIT[@]}"; do
  wait_for_service "$s" || true
done

log_section "Container status"
compose ps

log_section "Kafka topics"
if compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list; then
  :
else
  echo "  ! Unable to list topics (Kafka may still be initialising)."
fi

# Optional: safe topic bootstrap (ignores 'already exists')
if compose exec -T kafka test -x /opt/kafka/bin/kafka-topics.sh 2>/dev/null; then
  for t in ticket.requests payments.processed schedule.updates; do
    compose exec -T kafka /opt/kafka/bin/kafka-topics.sh \
      --bootstrap-server kafka:9092 --create --topic "$t" --if-not-exists --partitions 3 --replication-factor 1 || true
  done
fi

log_section "MongoDB connectivity"
if compose exec -T mongodb mongosh --quiet --eval "db.adminCommand({ ping: 1 })"; then
  :
else
  echo "  ! MongoDB ping failed (service may still be starting)."
fi

log_section "HTTP health checks"
if command -v curl >/dev/null 2>&1; then
  declare -a HEALTH_CHECKS=(
    "passenger-service|8080|passenger/health"
    "transport-service|8081|transport/health"
  )
  for item in "${HEALTH_CHECKS[@]}"; do
    IFS='|' read -r service internal_port path <<< "${item}"
    if ! host_port=$(get_host_port "${service}" "${internal_port}"); then
      echo "  ! Could not determine published port for ${service}:${internal_port}"
      continue
    fi
    local_url="http://localhost:${host_port}/${path}"
    success=false; last_body=""
    for _ in {1..12}; do
      status=$(curl -s -o /tmp/.hc_body -w "%{http_code}" "${local_url}" || true)
      last_body="$(head -c 300 /tmp/.hc_body || true)"
      if [[ "${status}" == "200" ]]; then
        echo "  ✔ ${service} responded 200 ${local_url}"
        echo "     ${last_body}"
        success=true; break
      fi
      sleep 5
    done
    if [[ "${success}" != true ]]; then
      echo "  ! ${service} did not return 200 from ${local_url} (last status: ${status:-n/a})"
      [[ -n "${last_body}" ]] && echo "     Body: ${last_body}"
    fi
  done
else
  echo "  ! 'curl' not found, skipping HTTP checks."
fi

log_section "Next steps"
echo "- View Kafka UI at http://localhost:8090"
echo "- Inspect service logs with: ${COMPOSE_CMD[*]} logs -f <service>"
echo "- Rebuild one service: ${COMPOSE_CMD[*]} up -d --build <service>"
echo "- Stop everything: ${COMPOSE_CMD[*]} down"

log_section "Done"
