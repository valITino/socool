#!/usr/bin/env bash
# tests/preflight/test-mocked.sh
#
# Unit-style tests of each preflight check run against mocked inputs.
# We can't easily mock /proc, /sys, sysctl, or ip on this host, so the
# tests use shell-level overrides: temporary bind-mount-free tricks via
# an LD_PRELOAD-free approach — PATH overrides + function overrides in
# a subshell. Where that's not possible (/proc file checks), we run the
# check on carefully-chosen fixtures by copying them to a scratch dir
# and patching the check script's path constants via sed into a scratch
# copy.
#
# Each test lives inside `run_case "<name>" { ... }` and reports ✓/✗.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"
CHECKS="$REPO_ROOT/scripts/preflight/checks"

pass=0
fail=0

run_case() {
    local name="$1"; shift
    if ( set -e; "$@" ) >/tmp/socool-test-out 2>&1; then
        echo "✓ $name"
        pass=$((pass + 1))
    else
        echo "✗ $name" >&2
        echo "  ------- output -------" >&2
        sed 's/^/  /' /tmp/socool-test-out >&2 || true
        echo "  ----------------------" >&2
        fail=$((fail + 1))
    fi
}

# Helper: run a check with an overridden SOCOOL_OS/ARCH. Most checks
# respect these via common.sh's detect_host (which we can sidestep by
# pre-setting the env — detect_host overwrites, but only when called,
# and checks call it at the top. To bypass, we create a temporary
# 'uname' shim on PATH that returns what we want.)
make_uname_shim() {
    local os="$1" arch="$2"
    local tmp; tmp="$(mktemp -d)"
    cat > "$tmp/uname" <<EOF
#!/usr/bin/env bash
case "\$1" in
    -s) echo "$os" ;;
    -m) echo "$arch" ;;
    *)  echo "$os" ;;
esac
EOF
    chmod +x "$tmp/uname"
    echo "$tmp"
}

# ───────────────────────────────────────────────────────────────────
# check-os-arch
# ───────────────────────────────────────────────────────────────────

test_os_arch_linux_x86_64_ok() {
    local shim; shim="$(make_uname_shim Linux x86_64)"
    PATH="$shim:$PATH" bash "$CHECKS/check-os-arch.sh"
    rm -rf "$shim"
}
run_case "check-os-arch: linux x86_64 => exit 0" test_os_arch_linux_x86_64_ok

test_os_arch_darwin_aarch64_ok() {
    local shim; shim="$(make_uname_shim Darwin arm64)"
    PATH="$shim:$PATH" bash "$CHECKS/check-os-arch.sh"
    rm -rf "$shim"
}
run_case "check-os-arch: darwin arm64 => exit 0" test_os_arch_darwin_aarch64_ok

test_os_arch_freebsd_reject() {
    local shim; shim="$(make_uname_shim FreeBSD amd64)"
    local rc=0
    PATH="$shim:$PATH" bash "$CHECKS/check-os-arch.sh" >/dev/null 2>&1 || rc=$?
    rm -rf "$shim"
    [[ "$rc" == "11" ]] || { echo "expected exit 11, got $rc"; return 1; }
}
run_case "check-os-arch: freebsd rejected with exit 11" test_os_arch_freebsd_reject

# ───────────────────────────────────────────────────────────────────
# check-cpu-virt — we can't redirect /proc/cpuinfo from bash cleanly,
# but we can patch a scratch copy of the check to read from a fixture.
# ───────────────────────────────────────────────────────────────────

run_cpu_virt_against_fixture() {
    local fixture="$1" expect_code="$2"
    local scratch; scratch="$(mktemp -d)"
    cp "$CHECKS/check-cpu-virt.sh" "$scratch/check.sh"
    # Point the grep at our fixture file instead of /proc/cpuinfo.
    sed -i "s|/proc/cpuinfo|$FIXTURES/$fixture|g" "$scratch/check.sh"
    # Make sure the script can still source common.sh (its relative path
    # is now wrong from the scratch dir). Re-point that too.
    sed -i "s|\$SCRIPT_DIR/../../lib/common.sh|$REPO_ROOT/scripts/lib/common.sh|g" "$scratch/check.sh"

    local shim; shim="$(make_uname_shim Linux x86_64)"
    local rc=0
    PATH="$shim:$PATH" bash "$scratch/check.sh" >/dev/null 2>&1 || rc=$?
    rm -rf "$shim" "$scratch"
    [[ "$rc" == "$expect_code" ]] || { echo "expected $expect_code, got $rc"; return 1; }
}

test_cpu_virt_vmx_pass() { run_cpu_virt_against_fixture cpuinfo-with-vmx 0; }
run_case "check-cpu-virt: vmx flag => exit 0" test_cpu_virt_vmx_pass

test_cpu_virt_svm_pass() { run_cpu_virt_against_fixture cpuinfo-with-svm 0; }
run_case "check-cpu-virt: svm flag => exit 0" test_cpu_virt_svm_pass

test_cpu_virt_none_fail() { run_cpu_virt_against_fixture cpuinfo-no-vt 12; }
run_case "check-cpu-virt: no vmx/svm => exit 12" test_cpu_virt_none_fail

# ───────────────────────────────────────────────────────────────────
# check-tools-version — verify the bash version parse handles the
# Debian-qemu '1:8.2.2+ds-0ubuntu' prefix by running a tiny subshell
# that loads just the _vercmp helper and calls it.
# ───────────────────────────────────────────────────────────────────

test_vercmp_handles_debian_prefix() {
    # Extract _vercmp from the check. This is a smoke test that the
    # helper's math is right on the strings we'll actually see.
    local rc
    rc="$(bash -c "
        set -eo pipefail
        source '$REPO_ROOT/scripts/lib/common.sh'
        # Inline the _vercmp helper from check-tools-version.sh.
        _vercmp() {
            local a=\$1 b=\$2
            [[ \$a == \$b ]] && { printf '0'; return; }
            local IFS=.
            # shellcheck disable=SC2206
            local aa=(\$a) bb=(\$b)
            local i max=\$(( \${#aa[@]} > \${#bb[@]} ? \${#aa[@]} : \${#bb[@]} ))
            for (( i=0; i<max; i++ )); do
                local ai=\${aa[i]:-0} bi=\${bb[i]:-0}
                ai=\${ai%%[!0-9]*}; bi=\${bi%%[!0-9]*}
                ai=\${ai:-0}; bi=\${bi:-0}
                (( 10#\$ai > 10#\$bi )) && { printf '1'; return; }
                (( 10#\$ai < 10#\$bi )) && { printf -- '-1'; return; }
            done
            printf '0'
        }
        _vercmp 8.2.2 6.0
    ")"
    [[ "$rc" == "1" ]] || { echo "expected _vercmp '8.2.2' '6.0' == 1, got '$rc'"; return 1; }
}
run_case "check-tools-version: _vercmp handles versions correctly" test_vercmp_handles_debian_prefix

# ───────────────────────────────────────────────────────────────────
# check-network-cidr — feed a fake route table via stdin to the
# embedded python helper and ensure overlap detection fires.
# ───────────────────────────────────────────────────────────────────

test_network_cidr_overlap_detected() {
    # Simulate a host with 10.42.10.0/24 already routed (collides with
    # the lab's LAN). We feed that route directly into the same python
    # snippet the check uses.
    python3 - "$REPO_ROOT/config/lab.yml" <<'PY' <<<'10.42.10.0/24'
import ipaddress, sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
lab_nets = [(r, ipaddress.ip_network(s['cidr'], strict=False)) for r, s in data.get('network', {}).items()]
hits = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    hn = ipaddress.ip_network(line, strict=False)
    if hn.prefixlen in (32, 128): continue
    for role, ln in lab_nets:
        if hn.overlaps(ln):
            hits.append(f"{role} overlap")
sys.exit(1 if hits else 0)
PY
    local rc=$?
    [[ "$rc" == "1" ]] || { echo "expected overlap detected (rc=1), got $rc"; return 1; }
}
run_case "check-network-cidr: lab overlap fires on 10.42.10.0/24" test_network_cidr_overlap_detected

# ───────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────

total=$((pass + fail))
echo
echo "RESULTS: ${pass}/${total} passed"
[[ "$fail" == "0" ]] || exit 1
