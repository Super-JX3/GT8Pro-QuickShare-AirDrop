from pathlib import Path
from textwrap import dedent
import subprocess,tempfile
p=Path(__file__).resolve().parent.parent/'module-template/payload';s=(p/'app-probe.sh').read_text();a=s.index('ui_wait_for_adopt(){');b=s.index('\n}',a)+2;fn=s[a:b]
with tempfile.TemporaryDirectory() as td:
 for mode,expected in [('transition',0),('never',1)]:
  script='''nfile="$1/count";mode="$2";echo 0 >"$nfile"
ui_state(){ n=$(cat "$nfile");n=$((n+1));echo "$n" >"$nfile";if [ "$mode" = transition ] && [ "$n" -ge 3 ];then echo TARGET_TOP;else echo PRESENT_OTHER_TOP;fi; }
sleep(){ :; }
'''+fn+'\nui_wait_for_adopt\n'
  r=subprocess.run(['sh','-c',script,'sh',td,mode]);assert r.returncode==expected,(mode,r.returncode)
 guard=(p/'app-guard.sh').read_text();a=guard.index('reason=EMERGENCY\nwhile :; do');b=guard.index('\nprintf ',a);loop=guard[a:b]
 Path(td,'binding-guard-abort.txt').write_text('ABORT\n')
 r=subprocess.run(['sh','-c','OUT=$1\n'+loop+'\nprintf "%s\\n" "$reason"','sh',td],capture_output=True,text=True,timeout=3)
 assert r.returncode==0 and r.stdout.strip()=='EMERGENCY',(r.returncode,r.stdout,r.stderr)
print('STARTUP_FOCUS_RETRY_AND_GUARD_ABORT=PASS')

# The app check may run while the native probe is preparing the private
# mount view. Neither a failed native probe nor a failed app check may launch.
namespace = (p/'namespace-bind.sh').read_text()
start = namespace.index('timeout -k 1 35 sh')
end = namespace.index('mosey_check_payload ||', start)
gate = namespace.index('sh "$MODDIR/load-probe.sh" action')
launch = namespace[start:end] + namespace[gate:]
for scenario in ('ready', 'app-failed', 'app-incomplete', 'native-failed'):
 with tempfile.TemporaryDirectory() as td:
    tmp = Path(td)
    (tmp/'precheck.sh').write_text(dedent('''
        for i in 1 2 3 4 5 6 7 8; do
            [ ! -f "$1/native-started" ] || break
            sleep .02
        done
        [ -f "$1/native-started" ] || exit 7
        [ "$SCENARIO" != app-failed ] || exit 1
        [ "$SCENARIO" != app-incomplete ] || exit 0
        echo BIND_PRECHECK=PASS
    '''))
    (tmp/'load-probe.sh').write_text(': >"$OUT/native-started"\n[ "$SCENARIO" != native-failed ]\n')
    (tmp/'service-bind.sh').write_text('echo REAL_SERVICE_STARTED\n')
    fixture = dedent('''
        OUT=$1
        MODDIR=$1
        GT8_BINDDIR=$1
        SCENARIO=$2
        export OUT SCENARIO
        timeout() { shift 3; "$@"; }
        gt8_ns_finish() { echo "RESULT=$1"; exit 1; }
    ''')
    r = subprocess.run(['sh','-c',fixture+launch,'sh',td,scenario],
                       capture_output=True,text=True,timeout=2)
    assert (r.returncode==0)==(scenario=='ready'), (scenario,r)
    assert ('REAL_SERVICE_STARTED' in r.stdout)==(scenario=='ready'), (scenario,r)
    assert ('APP_BINDING_PRECHECK_FAILED' in r.stdout)==scenario.startswith('app-'), (scenario,r)
print('PARALLEL_NATIVE_PREPARATION_ADMISSION=PASS')

# The window-manager event is narrowly filtered, even when an unrelated app
# or secondary user puts a similar activity name into the event stream.
watch = (p/'watch-daily.sh').read_text()
begin = watch.index('gt8_quick_share_event() {')
finish = watch.index('\n}\n', begin)+3
event_matcher = watch[begin:finish]
events = [
    ('wm_set_resumed_activity: [0,com.google.android.gms/.nearby.sharing.main.MainActivity,reason]', True),
    ('wm_set_resumed_activity: [0,com.google.android.gms/com.google.android.gms.nearby.sharing.receive.ReceiveActivity,reason]', True),
    ('wm_set_resumed_activity: [999,com.google.android.gms/.nearby.sharing.main.MainActivity,reason]', False),
    ('wm_set_resumed_activity: [0,unrelated/.nearby.sharing.main.MainActivity,reason]', False),
    ('wm_set_resumed_activity: [0,com.google.android.gms/.nearby.sharing.main.MainActivityClone,reason]', False),
    ('wm_on_resume_called: [0,com.google.android.gms/.nearby.sharing.main.MainActivity,reason]', False),
]
for event, expected in events:
    out = subprocess.run(['sh','-c',event_matcher+'\ngt8_quick_share_event "$1"','sh','123 I '+event])
    assert (out.returncode==0)==expected,(event,out)
print('QUICK_SHARE_EVENT_FILTER=PASS')

control = (p/'provider-control.sh').read_text()
start = control.index('provider_native_ready() {')
end = control.index('\n}\n', start)+3
with tempfile.TemporaryDirectory() as td:
    fixture = dedent('''\
        OUT=$1
        scenario=$2
        gt8_service_record() {
            SV_PID=42
            SV_TOKEN=123
            [ "$scenario" != replaced ] || SV_TOKEN=124
        }
        registration_identity() {
            [ "$1:$2" = 42:123 ] && [ ! -e "$OUT/exited" ]
        }
        registration_shim_success() { [ "$scenario" != unregistered ]; }
        timeout() {
            [ "$scenario" != missing ] || return 0
            echo 'Service com.google.android.moseyservice.IMoseyService/default: found'
            [ "$scenario" != exited ] || touch "$OUT/exited"
        }
        ''')
    for scenario in ('ready', 'replaced', 'missing', 'unregistered', 'exited'):
        script = fixture + control[start:end] + '\nprovider_native_ready 42 123\n'
        out = subprocess.run(['sh', '-c', script, 'sh', td, scenario], timeout=2)
        assert (out.returncode == 0) == (scenario == 'ready'), scenario
print('VERIFIED_NATIVE_PROVIDER_HANDOFF=PASS')
