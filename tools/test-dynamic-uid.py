from pathlib import Path
import os, subprocess, tempfile

root = Path(__file__).resolve().parent
common = root.parent / 'module-template/payload/bind-common.sh'
checks = root.parent / 'module-template/payload/updated-package-checks.sh'
with tempfile.TemporaryDirectory() as td:
    tmp = Path(td)
    bindir, proc = tmp / 'bin', tmp / 'proc'
    bindir.mkdir(); proc.mkdir()
    for name, script in {
        'timeout': '#!/bin/sh\nshift 3\n"$@"\n',
        'cmd': '#!/bin/sh\nprintf "%s\\n" "$TEST_PACKAGE_OUTPUT"\nexit "${TEST_CMD_RC:-0}"\n',
        'pidof': '#!/bin/sh\nprintf "%s\\n" "$TEST_PIDS"\n',
    }.items():
        p = bindir / name; p.write_text(script); p.chmod(0o755)

    def process(pid, uid):
        p = proc / str(pid); p.mkdir(exist_ok=True)
        (p / 'stat').write_text(f'{pid} (com.google.android.mosey) S ' + '0 ' * 18 + '1234 0\n')
        (p / 'status').write_text('Uid:\t' + '\t'.join([str(uid)] * 4) + '\n')
        (p / 'cmdline').write_bytes(b'com.google.android.mosey\0')
    process(111, 10432); process(222, 99910432); process(333, 99910366)
    env = {**os.environ, 'PATH': str(bindir)+':'+os.environ['PATH']}
    def call(function, output, pids='', rc='0'):
        env.update(TEST_PACKAGE_OUTPUT=output, TEST_PIDS=pids, TEST_CMD_RC=rc)
        return subprocess.run(['sh', '-c', '. "$1"; '+function, 'sh', str(common), str(proc)],
                              env=env, capture_output=True, text=True)
    pkg = 'package:com.google.android.mosey uid:'
    for uid in ('10366', '10432', '19999'):
        r=call('gt8_user0_mosey_uid', pkg+uid)
        assert r.returncode==0 and r.stdout.strip()==uid,(uid,r.stdout,r.stderr)
    for output in (pkg+'9999', pkg+'20000', pkg+'99910432', pkg+'x',
                   pkg+'10432\n'+pkg+'10432', 'package:wrong uid:10432'):
        assert call('gt8_user0_mosey_uid', output).returncode!=0,output
    assert call('gt8_user0_mosey_uid',pkg+'10432',rc='1').returncode!=0
    r=call('gt8_mosey_main_pids "$2"',pkg+'10432','111 222')
    assert r.returncode==0 and r.stdout.strip()=='111',(r.stdout,r.stderr)
    r=call('gt8_mosey_main_pids "$2"',pkg+'10432','222')
    assert r.returncode==0 and not r.stdout.strip(),(r.stdout,r.stderr)
    assert call('gt8_mosey_main_pids "$2"',pkg+'10432','111 333').returncode!=0

    required='NETWORK_FACTORY BLUETOOTH_PRIVILEGED CONNECTIVITY_USE_RESTRICTED_NETWORKS MANAGE_WIFI_INTERFACES LOCATION_HARDWARE INTERNET BLUETOOTH_SCAN BLUETOOTH_ADVERTISE NEARBY_WIFI_DEVICES ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION'.split()
    report=tmp/'profile.txt'
    report.write_text('CURRENT_CODE_PROFILE=PASS\nCURRENT_GOOGLE_SIGNER=PASS\nCURRENT_MOSEY_UID=10432\nCURRENT_PRIVILEGED=true\nCURRENT_PROFILE_RESULT=PASS\n'+''.join('CURRENT_PERMISSION='+x+' REQUESTED=YES GRANTED=YES\n' for x in required))
    def validate(uid):
        return subprocess.run(['sh','-c','. "$1"; updated_code_profile_ok "$2" "$3"','sh',str(checks),str(report),uid],capture_output=True).returncode
    assert validate('10432')==0
    for bad in ('10366','99910432','20000','abc',''):
        assert validate(bad)!=0,bad
    report.write_text(report.read_text()+'CURRENT_MOSEY_UID=10366\n')
    assert validate('10432')!=0
print('DYNAMIC_UID_PACKAGE_AND_USER_ISOLATION=PASS')
