#!/usr/bin/env bash
# tests/smoke/probes/windows-victim.sh
# Windows victim must expose either RDP (3389) or WinRM HTTP (5985).
set -euo pipefail
ip="10.42.10.20"
ok=0
for port in 3389 5985; do
    if timeout 5 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
        echo "[OK] windows-victim: TCP $ip:$port open"
        ok=1
    fi
done
if [[ "$ok" == "0" ]]; then
    echo "[FAIL] windows-victim: neither RDP (3389) nor WinRM (5985) reachable on $ip" >&2
    exit 72
fi
