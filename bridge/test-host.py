from pathlib import Path
import os, shutil
import subprocess,json,hashlib
root=Path(__file__).resolve().parent
build=root/'build'/'host-tests';build.mkdir(parents=True,exist_ok=True)
stub=root/'build'/'host-stub-src'
sources={
'android/content/pm/ApplicationInfo.java':'''package android.content.pm; public class ApplicationInfo { public String sourceDir; public String[] splitSourceDirs; public int uid; }''',
'android/os/SystemClock.java':'''package android.os; public final class SystemClock { public static long now=1; public static long elapsedRealtime(){return now;} }''',
'dalvik/system/BaseDexClassLoader.java':'''package dalvik.system; public class BaseDexClassLoader extends ClassLoader { public Object pathList; public BaseDexClassLoader(ClassLoader p){super(p);} public Class<?> make(String n,byte[] b){return defineClass(n,b,0,b.length);} }''',
'dalvik/system/DexFile.java':'''package dalvik.system; import java.util.*; public class DexFile { private String name; private String[] names; public DexFile(String n,String[] ns){name=n;names=ns;} public String getName(){return name;} public Enumeration<String> entries(){return Collections.enumeration(Arrays.asList(names));} }''',
}
for name,text in sources.items():
 p=stub/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
p=root/'build'/'fixture-src'/'fixture'/'Target.java';p.parent.mkdir(parents=True,exist_ok=True);p.write_text('package fixture; public class Target { public void harmless(){} }')
jdk=(Path(os.environ['JAVA_HOME'])/'bin' if os.environ.get('JAVA_HOME') else Path(shutil.which('java')).parent)
boot=build/'boot';boot.mkdir(exist_ok=True)
classes=build/'classes';classes.mkdir(exist_ok=True)
source_guard=(root/'src/local/gt8pro/moseybridge/SourceGuard.java').read_text()
real_hash='cf362969b16c1aac860e86deff8b425fcc50e3e68d6a1d4df5be686dbc79a9b7'
fixture_hash=hashlib.sha256(b'public-resource-fixture').hexdigest()
assert source_guard.count(real_hash)==1
test_guard=build/'test-src/local/gt8pro/moseybridge/SourceGuard.java'
test_guard.parent.mkdir(parents=True,exist_ok=True)
test_guard.write_text(source_guard.replace(real_hash,fixture_hash))
subprocess.run([str(jdk/'javac'),'-d',str(boot),*[str(x) for x in stub.rglob('*.java')]],check=True)
subprocess.run([str(jdk/'javac'),'-cp',str(boot),'-d',str(classes),str(root/'src/local/gt8pro/moseybridge/HookLogic.java'),str(test_guard),str(root/'src/local/gt8pro/moseybridge/ProbeLogic.java'),str(root/'src/local/gt8pro/moseybridge/RegistrationLogic.java'),str(root/'tests/HostTest.java'),str(p)],check=True)
r=subprocess.run([str(jdk/'java'),'-Xbootclasspath/a:'+str(boot),'-cp',str(classes),'local.gt8pro.moseybridge.HostTest',str(classes/'fixture/Target.class')],text=True,capture_output=True,check=True,timeout=10)
(build/'results.txt').write_text(r.stdout+r.stderr)
print(r.stdout,end='')
