#!/usr/bin/env bash
# tests/smoke/probes/kali.sh
# Kali SSH must accept a TCP connection on 10.42.10.10:22 and emit
# an SSH banner starting with 'SSH-'.
set -euo pipefail
ip="10.42.10.10"
port=22
if ! timeout 10 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
    echo "[FAIL] kali: TCP $ip:$port not reachable" >&2
    exit 71
fi
# Read the SSH banner (first 256 bytes) to distinguish 'port open but not
# sshd' from the real thing.
banner="$(timeout 5 bash -c "exec 3<>/dev/tcp/$ip/$port; head -c 256 <&3" 2>/dev/null || true)"
case "$banner" in
    SSH-*) echo "[OK] kali SSH banner: ${banner%%$'\r'*}" ;;
    *)     echo "[FAIL] kali: no SSH banner on $ip:$port (got: ${banner:0:80})" >&2; exit 71 ;;
esac
