#!/usr/bin/env python3
"""Exercise the production AWK against display and focus edge cases."""
from pathlib import Path
import subprocess
s=(Path(__file__).resolve().parent.parent/'module-template/payload/ui-common.sh').read_text()
a=s.index(" ) 2>&1 | awk '")+len(" ) 2>&1 | awk '");b=s.index("\n }')",a)+3
program=s[a:b]
activity='''ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)
  topResumedActivity=ActivityRecord{aa u0 com.google.android.gms/.nearby.sharing.main.MainActivity t1}
__UI_QUERY_RC=0
'''
header='WINDOW MANAGER DISPLAY CONTENTS (dumpsys window displays)\n'
primary='''  Display: mDisplayId=0 (organized)
  mCurrentFocus=Window{aa u0 com.google.android.gms/com.google.android.gms.nearby.sharing.main.MainActivity}
  mFocusedApp=ActivityRecord{aa u0 com.google.android.gms/.nearby.sharing.main.MainActivity t1}
'''
empty='''  Display: mDisplayId=5 (organized)
  mCurrentFocus=null
  mFocusedApp=null
'''
def check(displays,expected,ok=True,activities=activity):
 data=activities+header+displays+'WINDOW MANAGER DISPLAY CONTENTS (EXT)\n__WIN_QUERY_RC=0\n'
 r=subprocess.run(['awk',program],input=data,text=True,capture_output=True)
 assert r.stdout.strip()==expected and (r.returncode==0)==ok,(r.stdout,r.stderr,r.returncode)
check(primary,'TARGET_TOP')
check(empty+primary,'TARGET_TOP')
check(primary+empty,'TARGET_TOP')
check(empty.replace('mCurrentFocus=null','mCurrentFocus=Window{a u0 some.other/.Activity}')+primary,'UNCONFIRMED',False)
check(empty.replace('mFocusedApp=null','mFocusedApp=ActivityRecord{a u0 some.other/.Activity}')+primary,'UNCONFIRMED',False)
check(empty.replace('  mFocusedApp=null\n','')+primary,'UNCONFIRMED',False)
check(empty+primary+primary,'UNCONFIRMED',False)
settings=primary.replace('.main.MainActivity','.main.SettingsMainActivity')
settings_activity=activity.replace('.main.MainActivity','.main.SettingsMainActivity')
check(settings,'SETTINGS_TOP',activities=settings_activity)
check(settings,'PRESENT_OTHER_TOP')
check(settings.replace('mFocusedApp=ActivityRecord{aa u0 com.google.android.gms/.nearby.sharing.main.SettingsMainActivity',
                       'mFocusedApp=ActivityRecord{aa u0 com.google.android.gms/.nearby.sharing.main.MainActivity'),
      'ABSENT',activities=settings_activity)
check(settings.replace(' u0 ',' u10 '),'ABSENT',activities=settings_activity.replace(' u0 ',' u10 '))
print('UI_DISPLAY_FOCUS_POLICY=PASS')

script=s[s.index('ui_settings_send_state(){'):s.index('ui_close(){')]
fixture='''SERVICE com.google.android.gms/.chimera.PersistentApiServiceNoInstantApps example user=0
    com.google.android.gms.nearby.sharing.NearbySharingService
        Scanning: true
        Registered Send Surfaces:
    | Key | Value | Status | Start Time | End Time | Duration |
    +-----+-------+--------+------------+----------+----------+
    | 123 | FOREGROUND | ACTIVE | 12:05:41 | 00:00:00 | 0 |
        Fast Init Advertising: false
'''

def check_send(data, expected, exit_code=0):
 text='timeout(){ cat; return "${FIXTURE_RC:-0}"; }\n'+script+'\nui_settings_send_state'
 result=subprocess.run(['sh','-c',text],input=data,text=True,capture_output=True,
                       env={'PATH':'/usr/bin:/bin','FIXTURE_RC':str(exit_code)})
 assert result.stdout.strip()==expected and (result.returncode==0)==bool(expected),result

check_send(fixture,'TARGET_TOP')
check_send(fixture.replace('FOREGROUND','BACKGROUND'),'ABSENT')
check_send(fixture.replace('ACTIVE','STOPPED'),'ABSENT')
check_send(fixture.replace('Scanning: true','Scanning: false'),'ABSENT')
check_send(fixture.replace('user=0','user=10'),'')
check_send(fixture.replace('Registered Send','Registered Receive'),'')
check_send(fixture.replace('Fast Init Advertising:','Truncated output:'),'')
check_send(fixture.replace('| 123 |','| x |'),'')
check_send(fixture, '', exit_code=124)
check_send(fixture.replace('    | 123 | FOREGROUND | ACTIVE | 12:05:41 | 00:00:00 | 0 |\n',''),'ABSENT')
print('SETTINGS_FOREGROUND_SEND_SURFACE_POLICY=PASS')
for name in ('module-template/payload/watch-daily.sh','module-template/service.sh','module-template/payload/ui-lease-monitor.sh'):
 text=(Path(__file__).resolve().parent.parent/name).read_text();start=text.index('closed_safe(){');begin=text.index("| awk '",start)+len("| awk '");end=text.index("}'\n}",begin)+1;awk=text[begin:end]
 def closed(displays,expected):
  r=subprocess.run(['awk',awk],input=header+displays+'WINDOW MANAGER DISPLAY CONTENTS (EXT)\n__RC=0\n',text=True,capture_output=True)
  assert (r.returncode==0)==expected,(name,r.stdout,r.stderr,r.returncode)
 home=primary.replace('com.google.android.gms/com.google.android.gms.nearby.sharing.main.MainActivity','com.android.launcher/.Launcher').replace('com.google.android.gms/.nearby.sharing.main.MainActivity','com.android.launcher/.Launcher')
 closed(home,True);closed(empty+home,True);closed(home+empty,True)
 closed(empty.replace('mCurrentFocus=null','mCurrentFocus=Window{a u0 some.other/.Activity}')+home,False)
 closed(empty.replace('  mFocusedApp=null\n','')+home,False)
 closed(home.replace('com.android.launcher/.Launcher','com.android.intentresolver/.ChooserActivity')+empty,False)
print('UI_CLOSED_DISPLAY_POLICY=PASS')
