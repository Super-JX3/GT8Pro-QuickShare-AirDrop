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
