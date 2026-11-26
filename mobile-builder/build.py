#!/usr/bin/env python3
"""Build the offline Android module builder. No phone or network access."""
from pathlib import Path
import argparse,hashlib,json,os,re,secrets,shutil,subprocess,sys,tempfile,zipfile
ROOT=Path(__file__).resolve().parent; REPO=ROOT.parent
sys.path.insert(0, str(REPO/'bridge'))
from sdk_tools import extract_verified_sdk
sha=lambda b:hashlib.sha256(b).hexdigest()
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--tools',type=Path,required=True)
p.add_argument('--jdk-bin',type=Path,required=True)
p.add_argument('--signing',type=Path,required=True)
p.add_argument('--reference',type=Path,required=True,help='Authorized module ZIP matching the current source template')
p.add_argument('--bridge',type=Path,required=True,help='Signed companion bridge APK matching its module pin')
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
jdk=a.jdk_bin.resolve()
spec=json.loads((REPO/'external-inputs.json').read_text())['files']
def run(cmd,env=None):subprocess.run([str(x) for x in cmd],check=True,env=env,stdout=subprocess.DEVNULL)
sign=a.signing.resolve();sign.mkdir(mode=0o700,parents=True,exist_ok=True);pw=sign/'password.txt';ks=sign/'builder.p12'
if pw.is_symlink() or ks.is_symlink() or pw.exists()!=ks.exists():raise SystemExit('Invalid or incomplete signing identity')
env=os.environ.copy()
if not pw.exists():
 fd=os.open(pw,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
 with os.fdopen(fd,'w') as f:f.write(secrets.token_urlsafe(32))
 env['GT8_BUILDER_PASS']=pw.read_text()
 try:run([jdk/'keytool','-genkeypair','-keystore',ks,'-storetype','PKCS12','-alias','builder','-keyalg','RSA','-keysize','3072','-validity','3650','-dname','CN=GT8 Local Builder','-storepass:env','GT8_BUILDER_PASS','-keypass:env','GT8_BUILDER_PASS'],env);ks.chmod(0o600)
 except Exception:ks.unlink(missing_ok=True);pw.unlink(missing_ok=True);raise
env['GT8_BUILDER_PASS']=pw.read_text()
with tempfile.TemporaryDirectory() as t:
 stage=Path(t)
 sdk=extract_verified_sdk(a.tools.resolve(),stage/'sdk')
 bt=sdk/'android-16'; android=sdk/'android-36/android.jar'
 assets=stage/'assets';assets.mkdir(); classes=stage/'classes';classes.mkdir(); dex=stage/'dex';dex.mkdir();res=stage/'res/values';res.mkdir(parents=True)
 (res/'strings.xml').write_text('<resources><string name="app_name">Quick Share 模块构建助手</string></resources>')
 (stage/'AndroidManifest.xml').write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="local.gt8pro.builder" android:versionCode="4" android:versionName="0.3.0-dev"><uses-sdk android:minSdkVersion="36" android:targetSdkVersion="36"/><queries><package android:name="com.google.android.gms"/></queries><application android:label="@string/app_name" android:allowBackup="false" android:usesCleartextTraffic="false" android:theme="@android:style/Theme.Material.NoActionBar"><activity android:name=".BuilderActivity" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>''')
 with zipfile.ZipFile(a.reference) as z:
  if z.testzip() or len(z.namelist())!=len(set(z.namelist())):raise SystemExit('Invalid reference ZIP')
  notice=b'# Modified for the GT8 Pro adaptation; removed verbatim during assembly.\n'
  cnotice=b'/* Modified for the GT8 Pro adaptation; removed verbatim during assembly. */\n'
  expected_paths={f.relative_to(REPO/'module-template').as_posix() for f in (REPO/'module-template').rglob('*') if f.is_file()} | {x['path'] for x in spec}
  if set(z.namelist())!=expected_paths:raise SystemExit('Reference has unexpected or missing files')
  for f in (REPO/'module-template').rglob('*'):
   if not f.is_file():continue
   rel=f.relative_to(REPO/'module-template').as_posix()
   if rel in {x['path'] for x in spec}:continue
   data=f.read_bytes()
   if f.suffix in ('.sh','.awk','.c') or f.name in ('update-binary','sepolicy.rule'):
    marker=cnotice if f.suffix=='.c' else notice
    if data.count(marker)!=1:raise SystemExit('Invalid template notice: '+rel)
    data=data.replace(marker,b'',1)
   if z.read(rel)!=data:raise SystemExit('Reference differs from source template: '+rel)
  manifest=z.read('install.sha256');expected=(REPO/'module-template/install.sha256').read_bytes()
  if manifest!=expected:raise SystemExit('Reference does not match the checked-in candidate')
  for line in manifest.decode().splitlines():
   h,n=line.split(maxsplit=1)
   if sha(z.read(n))!=h:raise SystemExit('Reference manifest mismatch: '+n)
  for x in spec:
   if len(z.read(x['path']))!=x['size'] or sha(z.read(x['path']))!=x['sha256']:raise SystemExit('Reference component mismatch')
  with zipfile.ZipFile(assets/'template.zip','w',zipfile.ZIP_DEFLATED) as out:
   for name in sorted(z.namelist()):
    if not name.endswith('/'):out.writestr(name,z.read(name))
 pin_file=(REPO/'module-template/payload/check-helper.sh').read_text()
 pins=re.findall(r'^\[ "\$\{sum%% \*\}" = ([a-f0-9]{64}) \] \|\| exit 1$',pin_file,re.M)
 if not pins or sha(a.bridge.read_bytes()) != pins[-1]:raise SystemExit('Bridge APK does not match module pin')
 run([jdk/'java','-jar',bt/'lib/apksigner.jar','verify','--min-sdk-version','36',a.bridge])
 shutil.copyfile(a.bridge,assets/'bridge.apk')
 run([bt/'aapt2','compile','--dir',stage/'res','-o',stage/'compiled.zip'])
 run([bt/'aapt2','link','-I',android,'--manifest',stage/'AndroidManifest.xml','--min-sdk-version','36','--target-sdk-version','36','-o',stage/'resources.apk',stage/'compiled.zip'])
 java_sources=sorted((ROOT/'src').rglob('*.java'))+[
  REPO/'tools/gms-gate-proof/ProfileProof.java',
  REPO/'bridge/src/local/gt8pro/moseybridge/GmsProfile.java',
 ]
 run([jdk/'javac','-source','17','-target','17','-encoding','UTF-8','-cp',android,'-d',classes,*java_sources])
 with zipfile.ZipFile(stage/'classes.jar','w') as z:
  for f in sorted(classes.rglob('*.class')):z.write(f,f.relative_to(classes).as_posix())
 run([jdk/'java','-cp',bt/'lib/d8.jar','com.android.tools.r8.D8','--release','--min-api','36','--lib',android,'--output',dex,stage/'classes.jar'])
 with zipfile.ZipFile(stage/'resources.apk') as src,zipfile.ZipFile(stage/'unsigned.apk','w') as out:
  for info in src.infolist():out.writestr(info,src.read(info))
  out.writestr('classes.dex',(dex/'classes.dex').read_bytes())
  for f in assets.iterdir():out.write(f,'assets/'+f.name,compress_type=zipfile.ZIP_DEFLATED)
 run([bt/'zipalign','-P','16','-f','4',stage/'unsigned.apk',stage/'aligned.apk'])
 a.output.parent.mkdir(parents=True,exist_ok=True)
 run([jdk/'java','-jar',bt/'lib/apksigner.jar','sign','--ks',ks,'--ks-key-alias','builder','--ks-pass','env:GT8_BUILDER_PASS','--key-pass','env:GT8_BUILDER_PASS','--min-sdk-version','36','--v4-signing-enabled','false','--out',a.output,stage/'aligned.apk'],env)
 run([jdk/'java','-jar',bt/'lib/apksigner.jar','verify','--verbose',a.output]);run([bt/'zipalign','-c','-P','16','4',a.output])
print('BUILDER_APK='+str(a.output));print('SHA256='+sha(a.output.read_bytes()))
