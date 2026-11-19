from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent
entry=(root/'src/local/gt8pro/moseybridge/BridgeEntry.java').read_text()
assert 'deadline=Long.MAX_VALUE;' in entry
assert 'SESSION_EXPIRED' not in entry
assert 'SystemClock.elapsedRealtime()+15000' in entry
java='''import local.gt8pro.moseybridge.*;
public class LifetimeTest {
 public static void main(String[] args) {
  for(long now:new long[]{0L,86400000L,86400001L,3L*86400000L}) {
   if(!HookLogic.enable(true,true,now,Long.MAX_VALUE,false,Boolean.FALSE,0))throw new AssertionError("inactive after "+now);
   if(HookLogic.enable(true,false,now,Long.MAX_VALUE,false,Boolean.FALSE,0))throw new AssertionError("stopped hook active");
   if(!ProbeLogic.inspect(true,now,Long.MAX_VALUE,()->null).equals("REAL_BINDER_ABSENT"))throw new AssertionError("probe expired");
  }
  if(HookLogic.enable(true,true,15000,15000,false,Boolean.FALSE,0))throw new AssertionError("operation deadline bypassed");
  System.out.println("PROCESS_LIFETIME_AND_BOUNDED_DEADLINES=PASS");
 }
}'''
with tempfile.TemporaryDirectory() as t:
 tmp=Path(t);f=tmp/'LifetimeTest.java';f.write_text(java)
 subprocess.run(['javac','-d',str(tmp),str(root/'src/local/gt8pro/moseybridge/HookLogic.java'),str(root/'src/local/gt8pro/moseybridge/ProbeLogic.java'),str(f)],check=True)
 subprocess.run(['java','-cp',str(tmp),'LifetimeTest'],check=True)
