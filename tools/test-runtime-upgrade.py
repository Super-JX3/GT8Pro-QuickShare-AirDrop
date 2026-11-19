from pathlib import Path
import hashlib,os,subprocess,tempfile

source=(Path(__file__).resolve().parent.parent/'module-template/service.sh').read_text()
manifest=(Path(__file__).resolve().parent.parent/'module-template/payload.sha256').read_bytes()
digest=hashlib.sha256(manifest).hexdigest()
assert source.count(digest)==2, 'runtime directory and manifest checks must pin the same current manifest'
start=source.index('verify_dir(){\n');end=source.index('\nstatus_tmp=$(mktemp',start)
block=source[start:end].replace('0:700',f'{os.getuid()}:700').replace('0:600',f'{os.getuid()}:600')
with tempfile.TemporaryDirectory() as t:
 root=Path(t).resolve();bin=root/'bin';bin.mkdir()
 stat=bin/'stat';stat.write_text('#!/usr/bin/env python3\nimport os,sys,stat\ns=os.stat(sys.argv[-1]);print(f"{s.st_uid}:{stat.S_IMODE(s.st_mode):o}")\n');stat.chmod(0o755)
 module=root/'module';payload=module/'payload';payload.mkdir(parents=True);runtime=root/'daily';runtime.mkdir(mode=0o700)
 env={**os.environ,'PATH':str(bin)+':'+os.environ['PATH']}
 def prepare(content):
  (payload/'payload.sh').write_bytes(content)
  line=hashlib.sha256(content).hexdigest()+' payload.sh\n';(module/'payload.sha256').write_text(line)
  manifest=hashlib.sha256(line.encode()).hexdigest();return runtime/('runtime-integrated-'+manifest)
 def launch(d):
  s='module=$1; d=$2; root=$3; stage=\n'+block+'\n'
  return subprocess.run(['sh','-c',s,'sh',str(module),str(d),str(runtime)],env=env,capture_output=True,text=True)
 old=prepare(b'old payload\n');r=launch(old);assert r.returncode==0,(r.stdout,r.stderr)
 new=prepare(b'new payload\n');r=launch(new);assert r.returncode==0,(r.stdout,r.stderr)
 assert old!=new and (old/'payload.sh').read_bytes()==b'old payload\n' and (new/'payload.sh').read_bytes()==b'new payload\n'
 (new/'payload.sh').write_bytes(b'tampered\n');assert launch(new).returncode!=0
 assert (old/'payload.sh').read_bytes()==b'old payload\n'
print('CONTENT_ADDRESSED_UPGRADE_AND_TAMPER_REJECTION=PASS')
