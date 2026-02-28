#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PORT="${PORT:-3456}"
BASE_URL="http://127.0.0.1:${PORT}"
RETRY_COUNT="${RETRY_COUNT:-8}"
RETRY_DELAY="${RETRY_DELAY:-2}"

check_endpoint() {
  local endpoint="$1"
  local tmp_file http_code
  tmp_file="$(mktemp)"
  http_code="$(curl -sS --max-time 10 -o "$tmp_file" -w "%{http_code}" "${BASE_URL}${endpoint}" || true)"

  if [ "${http_code:-000}" != "200" ]; then
    echo "healthcheck ${endpoint} failed: http=${http_code:-000}, body=$(head -c 240 "$tmp_file")"
    rm -f "$tmp_file"
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.success == true' "$tmp_file" >/dev/null 2>&1; then
      echo "healthcheck ${endpoint} failed: success is not true, body=$(head -c 240 "$tmp_file")"
      rm -f "$tmp_file"
      return 1
    fi
  else
    if ! grep -q '"success":true' "$tmp_file"; then
      echo "healthcheck ${endpoint} failed: success is not true, body=$(head -c 240 "$tmp_file")"
      rm -f "$tmp_file"
      return 1
    fi
  fi

  rm -f "$tmp_file"
  return 0
}

for ((i=1; i<=RETRY_COUNT; i++)); do
  if check_endpoint "/api/stats"; then
    echo "healthcheck ok: /api/stats"
    exit 0
  fi

  if check_endpoint "/api/config"; then
    echo "healthcheck degraded: /api/stats failed but /api/config ok"
    exit 0
  fi

  if [ "$i" -lt "$RETRY_COUNT" ]; then
    sleep "$RETRY_DELAY"
  fi
done

echo "healthcheck failed: service not ready after ${RETRY_COUNT} attempts"
exit 1
