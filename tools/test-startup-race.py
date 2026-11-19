from pathlib import Path
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
