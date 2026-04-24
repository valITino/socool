#!/usr/bin/env bash
# tests/smoke/probes/wazuh.sh
# Wazuh dashboard must respond on https://10.42.20.10/.
set -euo pipefail
ip="10.42.20.10"
port=443
if ! timeout 10 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
    echo "[FAIL] wazuh: TCP $ip:$port not reachable" >&2
    exit 73
fi
code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 30 "https://$ip/" || echo "000")"
case "$code" in
    200|302) echo "[OK] wazuh dashboard: HTTP $code" ;;
    *) echo "[FAIL] wazuh: unexpected HTTP $code from https://$ip/" >&2; exit 73 ;;
esac
