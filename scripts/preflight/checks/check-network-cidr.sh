#!/usr/bin/env bash
# scripts/preflight/checks/check-network-cidr.sh
# Verifies none of the lab CIDRs (wan_sim, lan, management) overlap
# with a network already configured on the host.
# Exit 0 on pass; exit 18 on fail.
#
# CIDR math is done in Python (ipaddress stdlib), not regex, because
# a shell loop getting network boundaries wrong is exactly the kind
# of bug that produces intermittent routing heisenbugs.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

detect_host

# Gather the host's active networks into one CIDR-per-line string.
host_nets=""
case "$SOCOOL_OS" in
    linux)
        if command -v ip >/dev/null 2>&1; then
            # `ip -4 route show` prints "<net>/<prefix> ... dev ..."
            # for every route. Filter to lines that start with a CIDR.
            host_nets="$(ip -4 route show 2>/dev/null | awk '$1 ~ /\// { print $1 }')"
        else
            log_warn "iproute2 not installed; skipping network-CIDR probe"
            exit 0
        fi
        ;;
    darwin)
        # `netstat -rn -f inet` on macOS lists Destination/Gateway/.../Netif.
        # We convert dotted destinations + netmasks into CIDRs via python.
        host_nets="$(netstat -rn -f inet 2>/dev/null | awk '
            /^[0-9]/ && $1 !~ /^127\./ && $1 != "default" { print $1 }
        ')"
        ;;
    *)
        die 18 "check-network-cidr.sh should not run on os=$SOCOOL_OS; use check-network-cidr.ps1 on Windows."
        ;;
esac

# Pass host networks on stdin and lab CIDRs via argv to python.
# The script body lives in a temp file because mixing a heredoc and a
# pipe both targeting stdin is undefined: the last redirection wins,
# so the heredoc would silently swallow the piped host_nets.
overlap_script="$(mktemp -t socool-cidr-XXXXXX.py)"
trap 'rm -f -- "$overlap_script"' EXIT
cat > "$overlap_script" <<'PY'
import ipaddress, sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
lab_nets = []
for role, spec in (data.get('network') or {}).items():
    try:
        lab_nets.append((role, ipaddress.ip_network(spec['cidr'], strict=False)))
    except (ValueError, KeyError):
        continue

hits = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        hn = ipaddress.ip_network(line, strict=False)
    except ValueError:
        continue
    # Skip host-routes of a single address.
    if hn.prefixlen == 32 or hn.prefixlen == 128:
        continue
    for role, ln in lab_nets:
        if hn.overlaps(ln):
            hits.append(f"{role}={ln} overlaps host route {hn}")

if hits:
    for h in hits:
        print(h)
    sys.exit(1)
PY

overlap_rc=0
overlap="$(printf '%s\n' "$host_nets" | python3 "$overlap_script" "$socool_repo_root/config/lab.yml")" \
    || overlap_rc=$?

if [[ -n "${overlap:-}" ]]; then
    log_error "network-cidr overlap detected:"
    while IFS= read -r line; do
        [[ -n "$line" ]] && log_error "  $line"
    done <<< "$overlap"
    die 18 "lab CIDR conflicts with an existing host network; disconnect the conflicting interface, or edit config/lab.yml to pick different ranges."
fi

log_info "network-cidr: no overlaps with host routes"
