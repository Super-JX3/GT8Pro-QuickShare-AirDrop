#!/usr/bin/env python3
"""Check the restart button fails closed on ambiguous P2P state."""
from pathlib import Path
import shlex, subprocess
source = (Path(__file__).resolve().parent.parent / "module-template/payload/restart-service.sh").read_text()
fn = source[source.index("p2p_state() {"):source.index("\nstate=$(p2p_state)")]
for data, rc, expected in [
    ("mWifiP2pInfo groupFormed: true isGroupOwner: false\n", 0, "ACTIVE"),
    ("mWifiP2pInfo groupFormed: false isGroupOwner: false\n", 0, "IDLE"),
    ("", 0, ""),
    ("mWifiP2pInfo groupFormed: true x\nmWifiP2pInfo groupFormed: false x\n", 0, ""),
    ("mWifiP2pInfo groupFormed: true x\n", 1, ""),
]:
    timeout = 'shift 3; "$@";' if rc == 0 else "return 1;"
    script = "timeout() { " + timeout + " }\ndumpsys() { printf %s " + shlex.quote(data) + "; }\n" + fn + "\np2p_state\n"
    result = subprocess.run(["sh", "-c", script], capture_output=True, text=True)
    assert result.stdout.strip() == expected and (result.returncode == 0) == bool(expected), result
print("P2P_STATE_GUARD=PASS")
