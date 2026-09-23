#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

# Keep each service log from growing without bound (default 2MB, keep last 512KB).
LOG_MAX_BYTES="${LOG_MAX_BYTES:-2097152}"
LOG_KEEP_BYTES="${LOG_KEEP_BYTES:-524288}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BLUE=$'\033[34m'
  MAGENTA=$'\033[35m'
  CYAN=$'\033[36m'
  WHITE=$'\033[37m'
  BRIGHT_BLUE=$'\033[94m'
else
  RESET="" BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" BRIGHT_BLUE=""
fi

label() {
  local color="$1"
  local tag="$2"
  printf "%s%s[%s]%s" "$BOLD" "$color" "$tag" "$RESET"
}

say() {
  local tag_color="$1"
  local tag="$2"
  local message="$3"
  printf "%s %s\n" "$(label "$tag_color" "$tag")" "$message"
}

service_color() {
  case "$1" in
    configserver) printf "%s" "$BLUE" ;;
    eurekaserver) printf "%s" "$MAGENTA" ;;
    accounts) printf "%s" "$CYAN" ;;
    cards) printf "%s" "$YELLOW" ;;
    loans) printf "%s" "$GREEN" ;;
    message) printf "%s" "$WHITE" ;;
    gatewayserver) printf "%s" "$BRIGHT_BLUE" ;;
    *) printf "%s" "$CYAN" ;;
  esac
}

svc() {
  local name="$1"
  printf "%s%s%s%s" "$BOLD" "$(service_color "$name")" "$name" "$RESET"
}

# Prefer bundled portable kit (tools/) when present; else Scoop / system install.
if [[ -x "$ROOT/tools/jdk/bin/java" ]]; then
  export JAVA_HOME="$ROOT/tools/jdk"
fi
if [[ -z "${JAVA_HOME:-}" || ! -x "${JAVA_HOME}/bin/java" ]]; then
  if [[ -x "$HOME/scoop/apps/temurin21-jdk/current/bin/java" ]]; then
    export JAVA_HOME="$HOME/scoop/apps/temurin21-jdk/current"
  fi
fi

MVN_BIN="mvn"
if [[ -x "$ROOT/tools/maven/bin/mvn" ]]; then
  MVN_BIN="$ROOT/tools/maven/bin/mvn"
  export MAVEN_HOME="$ROOT/tools/maven"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${MAVEN_HOME:+$MAVEN_HOME/bin:}$HOME/scoop/apps/maven/current/bin:$PATH"

MVN_ARGS=()
if [[ -d "$ROOT/tools/m2" && -f "$ROOT/.mvn/settings-offline.xml" ]]; then
  MVN_ARGS+=(-o -s "$ROOT/.mvn/settings-offline.xml" -Dmaven.repo.local="$ROOT/tools/m2")
fi

if ! command -v "$MVN_BIN" >/dev/null 2>&1 && [[ ! -x "$MVN_BIN" ]]; then
  say "$RED" "FAIL" "Maven not found. Run prepare-offline.bat or install Maven."
  exit 1
fi

trim_log() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local size
  size="$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')"
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  if (( size > LOG_MAX_BYTES )); then
    tail -c "$LOG_KEEP_BYTES" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  fi
}

start_log_capper() {
  stop_log_capper
  (
    while true; do
      sleep 5
      shopt -s nullglob
      for f in "$LOG_DIR"/*.log; do
        trim_log "$f"
      done
    done
  ) &
  echo $! > "$LOG_DIR/logcap.pid"
}

stop_log_capper() {
  local pid_file="$LOG_DIR/logcap.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ -n "$pid" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$pid_file"
  fi
}

wait_port() {
  local port="$1"
  local name="$2"
  local i
  say "$YELLOW" "WAIT" "$(svc "$name") on port ${BOLD}${port}${RESET} ${DIM}(first start can take a few minutes)${RESET}"
  for i in $(seq 1 90); do
    trim_log "${LOG_DIR}/${name}.log"
    if curl -sf "http://127.0.0.1:${port}/actuator/health" >/dev/null 2>&1; then
      say "$GREEN" " UP " "$(svc "$name") is ready on ${BOLD}${port}${RESET}"
      return 0
    fi
    if command -v timeout >/dev/null 2>&1; then
      if timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1; then
        say "$GREEN" " UP " "$(svc "$name") is listening on ${BOLD}${port}${RESET}"
        return 0
      fi
    fi
    if (( i % 15 == 0 )); then
      say "$YELLOW" "WAIT" "$(svc "$name") still starting... ${DIM}${LOG_DIR}/${name}.log${RESET}"
    fi
    sleep 2
  done
  say "$RED" "FAIL" "$(svc "$name") timed out on port ${port}. See ${LOG_DIR}/${name}.log"
  return 1
}

start_service() {
  local module="$1"
  local log="${LOG_DIR}/${module}.log"
  local run_args=()
  say "$CYAN" "RUN " "Starting $(svc "$module")"
  : > "$log"
  case "$module" in
    accounts|message)
      run_args+=(
        -Dspring-boot.run.jvmArguments="-Dspring.cloud.function.autodetect=false -Dspring.cloud.function.definition= -Dlogging.level.org.apache.kafka=ERROR -Dlogging.level.org.springframework.kafka=ERROR -Dlogging.level.org.springframework.cloud.stream.binder.kafka=ERROR"
      )
      ;;
  esac
  nohup "$MVN_BIN" "${MVN_ARGS[@]}" -pl "$module" spring-boot:run \
    -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn \
    "${run_args[@]}" \
    > "$log" 2>&1 &
  echo $! > "${LOG_DIR}/${module}.pid"
}

stop_service() {
  local module="$1"
  local pid_file="${LOG_DIR}/${module}.pid"
  if [[ ! -f "$pid_file" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "$pid_file")"
  if [[ -n "$pid" ]]; then
    say "$MAGENTA" "STOP" "$(svc "$module") ${DIM}pid ${pid}${RESET}"
    if command -v taskkill >/dev/null 2>&1; then
      taskkill //F //T //PID "$pid" >/dev/null 2>&1 || true
    else
      kill "$pid" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$pid_file"
}

stop_all() {
  printf "\n%s%s Eazy Bank%s  stopping services\n\n" "$BOLD" "$MAGENTA" "$RESET"
  stop_log_capper
  for module in gatewayserver message loans cards accounts eurekaserver configserver; do
    stop_service "$module"
  done
  say "$GREEN" "DONE" "All services stopped."
}

print_summary() {
  printf "\n%s%s Eazy Bank%s  all services are up\n\n" "$BOLD" "$GREEN" "$RESET"
  printf "  %sconfigserver%s     http://localhost:8071\n" "$(service_color configserver)" "$RESET"
  printf "  %seurekaserver%s     http://localhost:8070\n" "$(service_color eurekaserver)" "$RESET"
  printf "  %saccounts%s         http://localhost:8080\n" "$(service_color accounts)" "$RESET"
  printf "  %scards%s            http://localhost:9000\n" "$(service_color cards)" "$RESET"
  printf "  %sloans%s            http://localhost:8090\n" "$(service_color loans)" "$RESET"
  printf "  %smessage%s          http://localhost:9010\n" "$(service_color message)" "$RESET"
  printf "  %sgatewayserver%s    %shttp://localhost:8072%s\n\n" "$(service_color gatewayserver)" "$BOLD$GREEN" "$RESET"
  say "$BLUE" "LOGS" "${DIM}${LOG_DIR}${RESET} ${DIM}(capped at $((LOG_MAX_BYTES / 1024))KB)${RESET}"
  say "$BLUE" "HINT" "Stop everything with ${BOLD}$0 stop${RESET}"
}

start_all() {
  printf "\n%s%s Eazy Bank%s  starting from %s\n\n" "$BOLD" "$CYAN" "$RESET" "$ROOT"

  start_log_capper

  start_service configserver
  wait_port 8071 configserver

  start_service eurekaserver
  wait_port 8070 eurekaserver

  start_service accounts
  wait_port 8080 accounts

  start_service cards
  wait_port 9000 cards

  start_service loans
  wait_port 8090 loans

  start_service message
  wait_port 9010 message

  start_service gatewayserver
  wait_port 8072 gatewayserver

  print_summary
}

case "${1:-start}" in
  start)
    start_all
    ;;
  stop)
    stop_all
    ;;
  *)
    say "$RED" "FAIL" "Usage: $0 [start|stop]"
    exit 1
    ;;
esac
