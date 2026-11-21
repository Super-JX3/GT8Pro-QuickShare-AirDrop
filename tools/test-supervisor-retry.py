from pathlib import Path
import subprocess, tempfile

source = (Path(__file__).resolve().parent.parent / 'module-template/service.sh').read_text()
start = source.index('(\n retries=0\n while :;do\n')
end = source.index(') 2>&1 | while IFS= read -r line;do', start) + 1
supervisor = source[start:end]
with tempfile.TemporaryDirectory() as module:
    test = '''
module=$1
calls=0
polls=0
sh() { calls=$((calls+1)); echo "TEST_WATCH_CALL=$calls"; return 1; }
sleep() { [ "$1" = 5 ] || exit 9; }
retry_quiet() { polls=$((polls+1)); [ "$polls" -gt 4 ]; }
wait_for_rearm() { echo TEST_REARM; return 1; }
''' + supervisor + '\n'
    result = subprocess.run(['sh', '-s', '--', module], input=test, text=True,
                            capture_output=True, timeout=5, check=True).stdout.splitlines()
assert result.count('WATCH_RETRY=BLOCKED') == 1, result
assert result.count('WATCH_RETRY=START') == 3, result
assert result.count('WATCH_RETRY=EXHAUSTED') == 1, result
assert result.count('TEST_REARM') == 1, result
assert [line for line in result if line.startswith('TEST_WATCH_CALL=')] == [
    'TEST_WATCH_CALL=1', 'TEST_WATCH_CALL=2', 'TEST_WATCH_CALL=3', 'TEST_WATCH_CALL=4'
], result
print('SUPERVISOR_RETRY_BUDGET=PASS')

start = source.index('watch_lock_retryable(){')
end = source.index('\nretry_quiet(){', start)
lock_check = source[start:end]
fixture = '''
stat() {
    case "$3" in
        */watch-lock) echo '0:700';;
        */watch-lock/owner) echo '0:600';;
        *) return 1;;
    esac
}
gt8_owner_alive() { [ "$1:$2" = '321:999' ]; }
'''
for record, expected in [(None, 0), ('321 123\n', 0), ('321 999\n', 1),
                         ('321 0\n', 1), ('321 123\n654 456\n', 1), ('', 1)]:
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp) / 'watch-lock'
        if record is not None:
            d.mkdir()
            (d / 'owner').write_text(record)
        r = subprocess.run(['sh','-c',fixture+lock_check+'\nwatch_lock_retryable "$1"','sh',tmp],
                           capture_output=True,text=True,timeout=2)
        assert r.returncode == expected, (record,r)
print('WATCH_RETRY_STALE_OWNER_ADMISSION=PASS')
