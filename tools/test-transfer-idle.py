import hashlib
from pathlib import Path
import subprocess

payload = Path(__file__).resolve().parents[1] / 'module-template' / 'payload'
shell = (payload / 'transfer-idle.sh').read_text()
parsers = {
    'runtime': shell.split(") 2>&1 | awk '\n", 1)[1].rsplit("\n' || exit 1", 1)[0],
    'standalone': (payload / 'gms-transfer-state.awk').read_text(),
}
header = '| Key | Value | Status | StartTime | EndTime | Duration |'
outgoing = '| 1 | receiver | | COMPLETE | start | end | duration |'
incoming = '| 2 | receiver | COMPLETE | start | end | duration |\n| | COMPLETE | | | | |'
prefix = '''SERVICE com.google.android.gms/.chimera.PersistentApiServiceNoInstantApps x user=0
com.google.android.gms.nearby.sharing.NearbySharingService
Outgoing Transfers:
'''
suffix = '''Registered providers:
com.google.android.gms.nearby.sharing.discovery.FastInitiation
__IDLE_RC=0
'''
for case, continuation, expected in (
    ('remote_cancelled', '| | REMOTE_CANCELLED | | | | |', 'IDLE'),
    ('complete', '| | COMPLETE | | | | |', 'IDLE'),
    ('in_progress', '| | IN_PROGRESS | | | | |', 'UNKNOWN'),
    ('connecting', '| | CONNECTING | | | | |', 'UNKNOWN'),
    ('unknown_status', '| | NEW_STATUS | | | | |', 'UNKNOWN'),
    ('missing_status', '', 'UNKNOWN'),
):
    fixture = '\n'.join((prefix, header, outgoing, continuation, 'Incoming Transfers:', header, incoming, suffix))
    for name, source in parsers.items():
        result = subprocess.run(['awk', source], input=fixture, capture_output=True, text=True)
        assert (result.returncode, result.stdout.strip()) == (0 if expected == 'IDLE' else 1,
                                                            f'TRANSFER_CLASS={expected}'), (name, case, result)
        print(name, case, expected)

# The watch, launch and manual recovery paths check the packaged bytes.
notice = b'# Modified for the GT8 Pro adaptation; removed verbatim during assembly.\n'
def packaged_hash(name):
    return hashlib.sha256((payload / name).read_bytes().replace(notice, b'', 1)).hexdigest()


transfer_hash = packaged_hash('transfer-idle.sh')
for checker in ('watch-daily.sh', 'restart-service.sh'):
    assert f'transfer-idle.sh:{transfer_hash}' in (payload / checker).read_text(), checker
launcher = (payload / 'main.sh').read_text()
for name in ('transfer-idle.sh', 'gms-transfer-state.awk'):
    assert f'{packaged_hash(name)}  $GT8_BINDDIR/{name}' in launcher, name
assert f'main.sh:{packaged_hash("main.sh")}' in (payload / 'watch-daily.sh').read_text()
print('PACKAGED_TRANSFER_CHECK_PINS=PASS')
