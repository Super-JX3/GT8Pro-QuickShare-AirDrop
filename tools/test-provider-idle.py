"""Check that a retained final transfer cannot block a quiet snapshot."""
from pathlib import Path
import subprocess


payload = Path(__file__).resolve().parents[1] / 'module-template/payload'
row = ('TransferState(targetId=fixture, shareTarget=fixture, transferJob=dyz{Completed}@ab12, '
       'transferId=fixture, onTransferUpdate=fixture, lastKnownMetadata=null, '
       'isTransferFinished=true, shareContentDeferred=dwv{Completed}@cd34)')
fixture = '''SERVICE com.google.android.mosey/.ExternalSharingService fixture user=0
  ExternalSharingService state:
    Send state: activeTransfers=[]
    --- Active Transfers ({count}) ---
{rows}
    #################################
    Receive provider BLE scanning: false
    Receive provider transferring: false
__DUMP_RC=0
'''


def check(sample, expected):
    run = subprocess.run(['awk', '-f', payload / 'provider-state.awk'], input=sample,
                         capture_output=True, text=True, timeout=5)
    assert run.stdout.strip() == f'PROVIDER_TRANSFER_CLASS={expected}', run
    assert (run.returncode == 0) == (expected == 'IDLE_SNAPSHOT'), run


one = fixture.format(count=1, rows=row)
check(fixture.format(count=0, rows=''), 'IDLE_SNAPSHOT')
check(one, 'IDLE_SNAPSHOT')
check(fixture.format(count=2, rows=f'{row}\n{row}'), 'IDLE_SNAPSHOT')
check(one.replace('isTransferFinished=true', 'isTransferFinished=false'), 'UNKNOWN')
check(one.replace('dyz{Completed}', 'dyz{Active}'), 'UNKNOWN')
check(one.replace('dwv{Completed}', 'dwv{Active}'), 'UNKNOWN')
check(one.replace('activeTransfers=[]', 'activeTransfers=[fixture]'), 'UNKNOWN')
check(one.replace('Receive provider transferring: false', 'Receive provider transferring: true'), 'UNKNOWN')
check(one.replace('Active Transfers (1)', 'Active Transfers (2)'), 'UNKNOWN')
check(one.replace('Active Transfers (1)', 'Active Transfers (0)'), 'UNKNOWN')
check(one.replace('lastKnownMetadata=null', 'lastKnownMetadata=isTransferFinished=true'), 'UNKNOWN')
check(one.replace('    Receive provider BLE scanning: false\n', ''), 'UNKNOWN')
check(one.replace('__DUMP_RC=0', '__DUMP_RC=124'), 'UNKNOWN')
print('PROVIDER_COMPLETED_TRANSFER_POLICY=PASS')
