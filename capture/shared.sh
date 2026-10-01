# shellcheck disable=SC2034
REMOTE_DIR=/tmp/vekrona-capture
SITE_ROOT="$REMOTE_DIR/site"
SITE_HOST=vekrona.com
SITE_PORT=443
SITE_TLS_DIR="$REMOTE_DIR/tls"
WAIT_FOR_ABORT_STATUS=70
INSTALLER_SCRIPT=install.sh
INSTALLER_ARGS=(--skip 10-nvidia 70)

wait_for() {
  local description="$1" timeout="$2"; shift 2
  local deadline=$((SECONDS + timeout)) output status
  until output="$("$@" 2>&1 </dev/null)"; do
    status=$?
    if [ "$status" -eq "$WAIT_FOR_ABORT_STATUS" ]; then
      echo "$description: $output" >&2
      return 1
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "timed out after ${timeout}s waiting for: $description${output:+ (last output: $output)}" >&2
      return 1
    fi
    sleep 0.2
  done
}
