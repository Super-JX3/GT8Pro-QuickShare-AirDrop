#!/usr/bin/env python3
"""Build one bounded GMS flag and real-Binder compatibility LSPosed APK. Never connects to a phone."""
from pathlib import Path
import argparse, hashlib, json, os, secrets, subprocess, zipfile, shutil

ROOT=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser()
 p.add_argument('--tools',type=Path,required=True)
 p.add_argument('--jdk',type=Path,required=True)
 p.add_argument('--out',type=Path,required=True)
 p.add_argument('--signing',type=Path,required=True)
 a=p.parse_args();tools=a.tools.resolve();jdk=a.jdk.resolve();out=a.out.resolve()
 sdk=tools/'sdk';android=sdk/'android-36/android.jar';bt=sdk/'android-16';api=tools/'api-82.jar'
 assert sha(api)=='f48c635f1c7469fdec0e00ad2ea0b7a6b2f5b55065784a35b7ca3a84615e8e25'
 expected={'platform-36_r02.zip':'2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576','build-tools_r36_macosx.zip':'199ae0047ee61e842f8ee0c6d3918e44fb9a1f83'}
 for n,h in expected.items():assert hashlib.sha1((tools/n).read_bytes()).hexdigest()==h
 for f in [android,bt/'aapt2',bt/'zipalign',bt/'lib/d8.jar',bt/'lib/apksigner.jar',jdk/'javac',jdk/'java',jdk/'keytool']:assert f.is_file(),f
 out.mkdir(parents=True,exist_ok=True)
 build=ROOT/'build';build.mkdir(exist_ok=True)
 logs=build/'build-log.txt'
 def run(cmd,env=None):
  r=subprocess.run([str(x) for x in cmd],capture_output=True,text=True,timeout=90,env=env)
  with logs.open('a') as log:log.write(r.stdout+r.stderr)
  if r.returncode:raise RuntimeError('Build command failed; inspect private build log')
  return r.stdout+r.stderr
 # This identity belongs only to this new local module. Never included in outputs.
 signing=a.signing.resolve();assert signing.is_dir();assert (signing/'password.txt').is_file() and (signing/'gt8-local.p12').is_file()
 pw=signing/'password.txt';ks=signing/'gt8-local.p12'
 if not pw.exists():
  fd=os.open(pw,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  with os.fdopen(fd,'w') as f:f.write(secrets.token_urlsafe(32))
 env=os.environ.copy();env['GT8_MODULE_SIGNING_PASS']=pw.read_text()
 if not ks.exists():
  run([jdk/'keytool','-genkeypair','-keystore',ks,'-storetype','PKCS12','-alias','gt8-local',
       '-keyalg','RSA','-keysize','3072','-validity','3650','-dname','CN=GT8 Pro Local Experimental Module',
       '-storepass:env','GT8_MODULE_SIGNING_PASS','-keypass:env','GT8_MODULE_SIGNING_PASS'],env)
  ks.chmod(0o600)
 rows=[]
 modes=[('transfer-test',True,True)]
 for mode,gms,binder in modes:
  stage=build/mode;stage.mkdir(exist_ok=True)
  classes=stage/'classes'
  if classes.exists():shutil.rmtree(classes)
  classes.mkdir()
  generated=stage/'generated/local/gt8pro/moseybridge';generated.mkdir(parents=True,exist_ok=True)
  (generated/'BuildVariant.java').write_text('package local.gt8pro.moseybridge; final class BuildVariant { static final String MODE="'+mode+'"; static final boolean GMS='+str(gms).lower()+', BINDER='+str(binder).lower()+', ROUTE=true; }\n')
  res=stage/'res/values';res.mkdir(parents=True,exist_ok=True)
  (res/'scope.xml').write_text('<resources><string-array name="scope"><item>com.google.android.gms</item><item>com.google.android.mosey</item></string-array></resources>')
  manifest=stage/'AndroidManifest.xml'
  manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="local.gt8pro.moseybridge" android:versionCode="1108" android:versionName="0.11.8-'''+mode+'''">
<uses-sdk android:minSdkVersion="36" android:targetSdkVersion="36"/>
<queries><package android:name="com.google.android.mosey"/></queries>
<application android:label="GT8 Pro Bridge · '''+mode+'''" android:allowBackup="false" android:debuggable="false" android:theme="@android:style/Theme.Material.Light.NoActionBar">
<meta-data android:name="xposedmodule" android:value="true"/>
<meta-data android:name="xposedminversion" android:value="82"/>
<meta-data android:name="xposeddescription" android:value="GT8 Pro 限时实验：'''+mode+'''；固定固件与 APK 身份，双进程86400秒到期，收发未验收"/>
<meta-data android:name="xposedscope" android:resource="@array/scope"/>
<activity android:name=".MainActivity" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>
<activity android:name=".ShareProbeActivity" android:exported="true"/>
<provider android:name=".FixtureProvider" android:authorities="local.gt8pro.moseybridge.fixture" android:exported="false" android:grantUriPermissions="true"/>
</application></manifest>''')
  compiled=stage/'compiled-res.zip'
  run([bt/'aapt2','compile','--dir',stage/'res','-o',compiled])
  resources=stage/'resources.apk'
  run([bt/'aapt2','link','-I',android,'--manifest',manifest,'--min-sdk-version','36','--target-sdk-version','36','-o',resources,compiled])
  run([jdk/'javac','-source','17','-target','17','-encoding','UTF-8','-cp',str(android)+os.pathsep+str(api),'-d',classes,
       *sorted((ROOT/'src').rglob('*.java')),generated/'BuildVariant.java'])
  jar=stage/'module-classes.jar'
  with zipfile.ZipFile(jar,'w') as z:
   for f in sorted(classes.rglob('*.class')):z.write(f,f.relative_to(classes).as_posix())
  dex=stage/'dex';dex.mkdir(exist_ok=True)
  run([jdk/'java','-cp',bt/'lib/d8.jar','com.android.tools.r8.D8','--release','--min-api','36','--lib',android,'--classpath',api,'--output',dex,jar])
  unsigned=stage/'unsigned.apk'
  with zipfile.ZipFile(resources) as source,zipfile.ZipFile(unsigned,'w') as z:
   for info in source.infolist():z.writestr(info,source.read(info))
   z.writestr('classes.dex',(dex/'classes.dex').read_bytes())
   z.writestr('assets/xposed_init','local.gt8pro.moseybridge.BridgeEntry\n')
  aligned=stage/'aligned.apk';run([bt/'zipalign','-P','16','-f','4',unsigned,aligned])
  target=out/('GT8Pro-MoseyBridge-0.11.8-'+mode+'.apk')
  run([jdk/'java','-jar',bt/'lib/apksigner.jar','sign','--ks',ks,'--ks-key-alias','gt8-local',
       '--ks-pass','env:GT8_MODULE_SIGNING_PASS','--key-pass','env:GT8_MODULE_SIGNING_PASS',
       '--min-sdk-version','36','--v4-signing-enabled','false','--out',target,aligned],env)
  verify=run([jdk/'java','-jar',bt/'lib/apksigner.jar','verify','--verbose','--print-certs',target])
  (stage/'signature-verification.txt').write_text(verify)
  run([bt/'zipalign','-c','-P','16','4',target])
  (out/(target.name+'.sha256')).write_text(sha(target)+'  '+target.name+'\n')
  rows.append({'file':target.name,'bytes':target.stat().st_size,'sha256':sha(target),'mode':mode,
       'gmsFalseToTrue':gms,'nativeLookupAdapter':binder,'deviceTested':False})
  print('BUILT',mode,'bytes='+str(target.stat().st_size),flush=True)
 receipt={'version':'0.11.8','package':'local.gt8pro.moseybridge','versionCode':1108,'scope':['com.google.android.gms','com.google.android.mosey'],
   'gmsLifetimeMs':86400000,'moseyLifetimeMs':86400000,'boundedSoakBuild':True,'reusableConcurrentDiscoverSlots':8,'reusableConcurrentSendSlots':4,'preparationBudgetMs':15000,'nativeAdapterReadyBeforeObservers':True,'nativeAdapterRequiresVerifiedApkHash':True,'mainThreadWaitAdded':False,'newLocalSigningIdentity':False,'reuseLocal060Signature':True,'appReadonlyNativeProbe':True,'discoverTaskObservation':True,'discoverThreadWaitClassification':True,'httpStatusObservation':True,'discoveryHttpProxyToDirect':True,'controlledSendAskUploadHttpProxyToDirect':True,'sendTaskObservation':True,'routeCompatibilityScope':'ORIGINAL_ROUTE_CONSTRUCTOR_SAME_DISCOVER_SLOT_HTTPS_LITERAL_LINK_LOCAL_EXACT_PATH','globalProxyOrVpnChanged':False,'originalTlsSocketObservation':True,'fixedTargetMetadataObservation':True,'originalRouteAndRawSocketObservation':True,'boundedTlsMessageClassification':True,'arbitraryThrowableMessageExport':False,'observeOriginalTlsFlag':False,'tlsConfigurationChanged':False,'requestOrResponseContentRead':True,'rawRequestOrResponseBodyRead':False,'requestBodyExport':False,'syntheticAskFixedMetadataEqualityOnly':True,'syntheticAskMetadataKeys':['Files','FileName','FileSize','FileType','SenderComputerName'],'maxObservedDiscoverTasks':8,'interfaceVersionTransaction':False,'explicitWaitLookupSelfTest':True,'originalApkResigned':False,
   'moseyVersionCode':60715,'registrationTaskObservation':False,'resourceOnlySplitAdmission':'PINNED_SHA256_NO_DEX','baseModulesReplaced':False,'nativeBinaryAdded':False,'permissionsRequested':[],
   'explicitRadioTriggers':False,'explicitFileTransfer':True,'syntheticSystemShareEntry':True,'syntheticProviderPrivate':True,'syntheticFixtureReadGrantToMosey':True,'syntheticFixtureGrantExplicitRevoke':True,'syntheticFixtureRootControlOnly':True,'syntheticFixtureGrantEffectiveUidCheck':'PACKAGE_MANAGER_USER_0','syntheticFixtureQueryPackage':'com.google.android.mosey','syntheticFixtureReadContextObservation':True,'syntheticShareFixtureStorage':'APP_OWNED_MEDIASTORE_DOWNLOADS','syntheticMediaFixtureBytes':8192,'syntheticFixtureRevokeAllReadGrants':True,'receiveRequestObservation':True,'receiveTransportObservation':True,'gmsMayNaturallyInitializeWireless':True,'networkPermissionGap':'NETWORK_FACTORY_GRANTED_FUTURE_DEFINITIONS_ABSENT',
   'gmsBaseSha256':'0a0af2a2c44c459a0dded52cb7e176704d640ae738980d12360697cf96c8da4e',
   'moseyBaseSha256':'7ab2deaea6c9c2bdd5ba0f935d6143c115f5ceb11cb8b63066496ad27a28da49',
   'toolchain':{'platformArchiveSha1':expected['platform-36_r02.zip'],'buildToolsArchiveSha1':expected['build-tools_r36_macosx.zip'],'xposedApiSha256':sha(api)},'files':rows,'sources':{str(f.relative_to(ROOT)):sha(f) for f in sorted((ROOT/'src').rglob('*.java'))}}
 (out/'GT8Pro-MoseyBridge-0.11.8-Provenance.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
 print('BUILD_COMPLETE; no phone operations performed')
if __name__=='__main__':main()
