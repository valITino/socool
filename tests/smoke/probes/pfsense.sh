#!/usr/bin/env bash
# tests/smoke/probes/pfsense.sh
# pfSense webConfigurator must respond on https://10.42.20.1/ (management).
set -euo pipefail
ip="10.42.20.1"
port=443
if ! timeout 10 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
    echo "[FAIL] pfsense: TCP $ip:$port not reachable" >&2
    exit 70
fi
# -k = accept the self-signed cert pfSense ships; -s silent; -o /dev/null
# discards body; -w captures the status code; --max-time bounds runtime.
code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 15 "https://$ip/" || echo "000")"
case "$code" in
    200|301|302) echo "[OK] pfsense webConfigurator: HTTP $code" ;;
    *) echo "[FAIL] pfsense: unexpected HTTP $code from https://$ip/" >&2; exit 70 ;;
esac
