#!/usr/bin/env bash
# tests/smoke/probes/nessus.sh
# Nessus web UI on :8834. Plugin loader may make the first response
# slow; we wait up to 60 seconds.
set -euo pipefail
ip="10.42.20.20"
port=8834
if ! timeout 10 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
    echo "[FAIL] nessus: TCP $ip:$port not reachable" >&2
    exit 74
fi
code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 60 "https://$ip:$port/" || echo "000")"
case "$code" in
    200|302) echo "[OK] nessus UI: HTTP $code" ;;
    *) echo "[FAIL] nessus: unexpected HTTP $code from https://$ip:$port/" >&2; exit 74 ;;
esac
