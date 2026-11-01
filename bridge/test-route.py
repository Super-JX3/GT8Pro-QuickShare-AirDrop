from pathlib import Path
import os, shutil
import subprocess
root=Path(__file__).resolve().parent;jdk=(Path(os.environ['JAVA_HOME'])/'bin' if os.environ.get('JAVA_HOME') else Path(shutil.which('java')).parent);out=root/'build/route-tests';out.mkdir(parents=True,exist_ok=True)
subprocess.run([str(jdk/'javac'),'-d',str(out),str(root/'src/local/gt8pro/moseybridge/DiscoveryRouteLogic.java'),str(root/'tests/RouteLogicTest.java')],check=True)
r=subprocess.run([str(jdk/'java'),'-cp',str(out),'local.gt8pro.moseybridge.RouteLogicTest'],capture_output=True,text=True,check=True,timeout=10);(out/'results.txt').write_text(r.stdout);print(r.stdout,end='')
