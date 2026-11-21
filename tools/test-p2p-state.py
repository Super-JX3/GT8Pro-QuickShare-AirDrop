#!/usr/bin/env python3
"""Exercise status and guarded Wi-Fi Direct release with simulated system commands."""
from pathlib import Path
import shlex
import subprocess

root = Path(__file__).resolve().parent.parent
source = (root / 'module-template/payload/restart-service.sh').read_text()
functions = source[source.index('p2p_state() {'):source.index('\n[ "$#" = 1 ]')]
active = 'mWifiP2pInfo groupFormed: true isGroupOwner: false\n'
idle = 'mWifiP2pInfo groupFormed: false isGroupOwner: false\n'


def run(stubs, action):
    result = subprocess.run(
        ['sh', '-c', functions + '\n' + stubs + '\n' + action],
        capture_output=True, text=True, timeout=5)
    return result.returncode, result.stdout.strip(), result.stderr.splitlines()


for data, rc, expected in [
    (active, 0, 'ACTIVE'), ('    ' + idle, 0, 'IDLE'),
    ('', 0, ''), (active + idle, 0, ''),
    ('mWifiP2pInfo groupFormed: true x\n', 0, ''),
    (active + 'Permission Denial\n', 0, ''), (active, 1, ''),
]:
    code, output, _ = run(
        f'timeout() {{ printf %s {shlex.quote(data)}; return {rc}; }}', 'p2p_state')
    assert (code == 0, output) == (bool(expected), expected), (data, rc, code, output)

stubs = """
timeout() { shift 3; "$@"; }
dumpsys() { printf '%s\n' 'mWifiP2pInfo groupFormed: true isGroupOwner: false'; }
service() { printf 'Service %s: found\n' "$2"; }
ip() {
    printf '%s\n' '1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536' \
        '4: p2p0: <BROADCAST,UP,LOWER_UP> mtu 1500' "$link"
}
cmd() { echo "unexpected cmd" >&2; return 1; }
"""
for extra, expected in [
    ('', 'ABSENT'),
    ('link="6: wonder0: <BROADCAST> mtu 1500"', 'DOWN'),
    ('link="6: wonder0@wlan0: <BROADCAST,UP> mtu 1500"', 'UP'),
    ('ip() { return 1; }', 'UNKNOWN'),
]:
    assert run(stubs + extra, 'snapshot') == (
        0, 'STATUS P2P=ACTIVE BINDER=PRESENT RADIO=' + expected, [])

recovery = """
exec 3>&2
timeout() { shift 3; "$@"; }
sleep() { :; }
pidof() { return 1; }
cmd() {
    printf '%s\n' "$2" >&3
    case "$2" in
        init) mock_radio=AFTER_INIT ;;
        remove-group) mock_radio=AFTER_RELEASE ;;
    esac
}
transfer_idle() { [ "$mock_radio" != AFTER_INIT ] || [ "$scenario" != busy_after_init ]; }
service_idle() { [ "$scenario:$mock_radio" != active: ] && [ "$scenario:$mock_radio" != active_after_init:AFTER_INIT ]; }
p2p_state() {
    case "$scenario:$mock_radio" in
        unknown:|unknown_after_init:AFTER_INIT) return 1 ;;
        idle:|*:AFTER_RELEASE) echo IDLE ;;
        *) echo ACTIVE ;;
    esac
}
"""
for scenario, code, outcome, actions in [
    ('active', 1, 'SERVICE_ACTIVE', []),
    ('unknown', 1, 'P2P_RELEASE_FAILED', []),
    ('idle', 0, 'RESTART_READY', []),
    ('active_after_init', 1, 'SERVICE_ACTIVE', ['init', 'deinit']),
    ('busy_after_init', 1, 'TRANSFER_BUSY', ['init', 'deinit']),
    ('unknown_after_init', 1, 'P2P_RELEASE_FAILED', ['init', 'deinit']),
    ('released', 0, 'RESTART_READY', ['init', 'remove-group', 'deinit']),
]:
    assert run(recovery, f'scenario={scenario}; reclaim') == (code, outcome, actions), scenario
print('P2P_STATUS_AND_RECOVERY_GUARDS=PASS')
