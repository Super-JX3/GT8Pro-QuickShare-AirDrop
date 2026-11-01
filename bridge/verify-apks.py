from pathlib import Path
import hashlib,json,struct,subprocess,zipfile,sys
root=Path(__file__).resolve().parent
out=Path(sys.argv[1]).resolve()
receipt=json.loads((out/'GT8Pro-MoseyBridge-0.11.6-Provenance.json').read_text())
checks=0
for item in receipt['files']:
 p=out/item['file'];assert hashlib.sha256(p.read_bytes()).hexdigest()==item['sha256'];checks+=1
 with zipfile.ZipFile(p) as z:
  assert z.testzip() is None
  assert len(z.namelist())==len(set(z.namelist()))
  assert z.read('assets/xposed_init')==b'local.gt8pro.moseybridge.BridgeEntry\n'
  assert not any(n.startswith('lib/') or n.endswith(('.so','.sh')) for n in z.namelist());checks+=4
  d=z.read('classes.dex')
  assert d[:8] in [b'dex\n039\0',b'dex\n040\0']
  assert struct.unpack_from('<I',d,32)[0]==len(d)
  def u4(p):return struct.unpack_from('<I',d,p)[0]
  def uleb(p):
   v=0;s=0
   while True:
    c=d[p];p+=1;v|=(c&127)<<s;s+=7
    if c<128:return v,p
    assert s<35
  count,offset=u4(56),u4(60);strings=[]
  for i in range(count):
   _,at=uleb(u4(offset+i*4));strings.append(d[at:d.index(0,at)].decode('utf8'))
  types=[strings[u4(u4(68)+i*4)] for i in range(u4(64))]
  classes=[];build=None
  for i in range(u4(96)):
   at=u4(100)+32*i;name=types[u4(at)];classes.append(name)
   if name=='Llocal/gt8pro/moseybridge/BuildVariant;':build=at
  assert classes and all(x.startswith('Llocal/gt8pro/moseybridge/') for x in classes)
  assert not any(x.startswith(('Landroid/','Ldalvik/','Lde/robv/')) for x in classes);checks+=2
  assert build is not None
  at=u4(build+24);nums=[]
  for _ in range(4):n,at=uleb(at);nums.append(n)
  fields=[];index=0
  for _ in range(nums[0]):
   delta,at=uleb(at);_,at=uleb(at);index+=delta
   field=u4(84)+8*index;fields.append(strings[u4(field+4)])
  at=u4(build+28);n,at=uleb(at);values=[]
  for _ in range(n):
   byte=d[at];at+=1;kind=byte&31;arg=byte>>5
   if kind==31:value=bool(arg)
   elif kind==23:
    value=strings[int.from_bytes(d[at:at+arg+1],'little')];at+=arg+1
   else:raise AssertionError('Unexpected variant constant')
   values.append(value)
  actual=dict(zip(fields,values))
  assert actual=={'BINDER':item['nativeLookupAdapter'],'GMS':item['gmsFalseToTrue'],'MODE':item['mode'],'ROUTE':True},actual
  checks+=1
  print('APK_VERIFIED',item['mode'],'classes='+str(len(classes)),'flags='+str(actual))
 aapt=Path(__import__('os').environ['GT8_ANDROID_TOOLS'])/'sdk/android-16/aapt2'
 badging=subprocess.run([str(aapt),'dump','badging',str(p)],capture_output=True,text=True,check=True).stdout
 assert "package: name='local.gt8pro.moseybridge'" in badging
 assert "versionCode='"+str(receipt['versionCode'])+"'" in badging
 assert "versionName='0.11.6-"+item['mode']+"'" in badging
 assert "minSdkVersion:'36'" in badging and "targetSdkVersion:'36'" in badging
 assert 'uses-permission' not in badging
 checks+=4
 xml=subprocess.run([str(aapt),'dump','xmltree',str(p),'--file','AndroidManifest.xml'],capture_output=True,text=True,check=True).stdout
 import re
 components=[];current=None;level=0
 for line in xml.splitlines():
  indent=len(line)-len(line.lstrip())
  m=re.match(r'\s*E: (activity|provider) \(',line)
  if m:
   current={'kind':m[1]};components.append(current);level=indent;continue
  if current is not None:
   if line.strip() and indent<=level:current=None;continue
   m=re.search(r'android:(name|authorities|exported|grantUriPermissions)\([^)]*\)=(.*)$',line)
   if m and indent==level+2:current[m[1]]=m[2].split(' (Raw:')[0].strip('"')
 activities={c['name']:c for c in components if c['kind']=='activity'}
 providers=[c for c in components if c['kind']=='provider']
 assert set(activities)=={'.MainActivity','.ShareProbeActivity'}
 assert all(c.get('exported')=='true' for c in activities.values())
 assert len(providers)==1 and providers[0]['name']=='.FixtureProvider'
 assert providers[0].get('exported')=='false' and providers[0].get('grantUriPermissions')=='true'
 assert providers[0].get('authorities')=='local.gt8pro.moseybridge.fixture'
 checks+=5
 assert not (out/(p.name+'.idsig')).exists();checks+=1
assert len(set(x['sha256'] for x in receipt['files']))==1
assert all(x['deviceTested'] is False for x in receipt['files'])
checks+=2
print('APK_STRUCTURE_CHECKS_PASS='+str(checks))
print('APK_TARGET_CLASSES_EXECUTED=false')
