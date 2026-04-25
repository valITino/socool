#!/usr/bin/env bash
# tests/smoke/probes/openvas.sh
# Greenbone web UI on https://10.42.20.20/. Containers may take a
# minute to initialise on first boot.
set -euo pipefail
ip="10.42.20.20"
port=443
if ! timeout 10 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
    echo "[FAIL] openvas: TCP $ip:$port not reachable" >&2
    exit 75
fi
code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 60 "https://$ip/" || echo "000")"
case "$code" in
    200|301|302) echo "[OK] openvas UI: HTTP $code" ;;
    *) echo "[FAIL] openvas: unexpected HTTP $code from https://$ip/" >&2; exit 75 ;;
esac
