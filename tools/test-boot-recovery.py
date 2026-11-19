from pathlib import Path
import os,subprocess,tempfile
source=(Path(__file__).resolve().parent.parent/'module-template/payload/watch-daily.sh').read_text()
func=source[source.index('gt8_prepare_idle_boot_process(){'):source.index('\nGT8_WATCHER_PID=$$')]
with tempfile.TemporaryDirectory() as tmp:
 base=Path(tmp); proc=base/'proc/123'; (proc/'attr').mkdir(parents=True)
 (proc/'stat').write_text('123 (com.google.android.mosey) S '+' '.join(['0']*18)+' 1234 0\n')
 (proc/'attr/current').write_text('u:r:mosey_app:s0:c1,c2')
 (base/'root').mkdir(); (base/'pid').write_text('123')
 func=func.replace('/proc/$p/',str(proc.parent)+'/$p/')
 stub='''
root="$T/root";d="$T";ui_state(){ echo "${UI:-TARGET_TOP}"; }
gt8_mosey_main_pids(){ cat "$T/pid"; };gt8_user0_mosey_uid(){ echo 10366; }
pidof(){ :; };sh(){ case "$1" in */current-code-profile.sh) echo "${PROFILE:-CURRENT_PROFILE_RESULT=PASS}";; *) echo "${TRANSFER:-TRANSFER_CLASS=IDLE}";; esac; };sleep(){ :; }
gt8_main_services_view(){ cat; }
timeout(){ shift 3; case "$1" in
 cmd) echo "${PROVIDER:-No services found}";;
 service) echo "Service $3: ${BINDER:-not found}";;
 dumpsys) printf '%s\\n' 'ACTIVITY MANAGER SERVICES';;
 am) : >"$T/pid";echo STOPPED >>"$T/actions";;
 *) return 1;;esac; }
'''
 for name,extra,expected in [('idle',{},0),('bad_profile',{'PROFILE':'CURRENT_PROFILE_RESULT=FAIL'},1),('busy',{'TRANSFER':'TRANSFER_CLASS=UNKNOWN'},1),('provider',{'PROVIDER':'present'},1),('binder',{'BINDER':'found'},1),('background',{'UI':'ABSENT'},1),('ambiguous_process',{'PID':'123 124'},1)]:
  (base/'pid').write_text(extra.pop('PID','123')); (base/'actions').unlink(missing_ok=True)
  r=subprocess.run(['sh','-c',stub+func+'\ngt8_prepare_idle_boot_process\n'],env={**os.environ,'T':tmp,**extra},capture_output=True,text=True)
  assert (r.returncode==0)==(expected==0),(name,r.returncode,r.stdout,r.stderr)
  assert (base/'actions').exists()==(expected==0),name
print('IDLE_BOOT_RECOVERY_ADMISSION=PASS')
