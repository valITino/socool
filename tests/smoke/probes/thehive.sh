#!/usr/bin/env bash
# tests/smoke/probes/thehive.sh
# TheHive web UI on https://10.42.20.30/. Cassandra + Elasticsearch
# initialisation can take several minutes after first boot before the
# stack is reachable; the timeout reflects that.
set -euo pipefail
ip="10.42.20.30"
port=443
if ! timeout 10 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
    echo "[FAIL] thehive: TCP $ip:$port not reachable" >&2
    exit 76
fi
code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 60 "https://$ip/" || echo "000")"
case "$code" in
    200|301|302) echo "[OK] thehive UI: HTTP $code" ;;
    *) echo "[FAIL] thehive: unexpected HTTP $code from https://$ip/" >&2; exit 76 ;;
esac
