#!/usr/bin/env python3
"""Exercise the production AWK against display and focus edge cases."""
from pathlib import Path
import subprocess
s=(Path(__file__).resolve().parent.parent/'module-template/payload/ui-common.sh').read_text()
a=s.index(" ) 2>&1 | awk '")+len(" ) 2>&1 | awk '");b=s.index("\n }'\n}",a)+3
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
def check(displays,expected,ok=True):
 data=activity+header+displays+'WINDOW MANAGER DISPLAY CONTENTS (EXT)\n__WIN_QUERY_RC=0\n'
 r=subprocess.run(['awk',program],input=data,text=True,capture_output=True)
 assert r.stdout.strip()==expected and (r.returncode==0)==ok,(r.stdout,r.stderr,r.returncode)
check(primary,'TARGET_TOP')
check(empty+primary,'TARGET_TOP')
check(primary+empty,'TARGET_TOP')
check(empty.replace('mCurrentFocus=null','mCurrentFocus=Window{a u0 some.other/.Activity}')+primary,'UNCONFIRMED',False)
check(empty.replace('mFocusedApp=null','mFocusedApp=ActivityRecord{a u0 some.other/.Activity}')+primary,'UNCONFIRMED',False)
check(empty.replace('  mFocusedApp=null\n','')+primary,'UNCONFIRMED',False)
check(empty+primary+primary,'UNCONFIRMED',False)
print('UI_DISPLAY_FOCUS_POLICY=PASS')
for name in ('module-template/payload/watch-daily.sh','module-template/service.sh'):
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
