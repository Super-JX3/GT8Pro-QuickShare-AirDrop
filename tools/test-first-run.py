from pathlib import Path
import os, subprocess, tempfile

script=(Path(__file__).resolve().parent.parent/'module-template/service.sh').read_text()
start=script.index('prepare_service_root(){\n')
end=script.index('\nprepare_service_root /data/adb/gt8pro-mosey-service',start)
function=script[start:end].replace('= 0:700',f'= {os.getuid()}:700')
with tempfile.TemporaryDirectory() as t:
 root=Path(t).resolve();bindir=root/'bin';bindir.mkdir()
 stat=bindir/'stat';stat.write_text('#!/usr/bin/env python3\nimport os,sys,stat\ns=os.stat(sys.argv[-1]);print(f"{s.st_uid}:{stat.S_IMODE(s.st_mode):o}")\n');stat.chmod(0o755)
 env={**os.environ,'PATH':str(bindir)+':'+os.environ['PATH']}
 def check(path):return subprocess.run(['sh','-c',function+'\nprepare_service_root "$1"','sh',str(path)],env=env,capture_output=True).returncode
 fresh=root/'service';assert not fresh.exists();assert check(fresh)==0;assert fresh.is_dir() and fresh.stat().st_mode & 0o777==0o700
 assert check(fresh)==0
 bad=root/'bad';bad.mkdir(mode=0o755);assert check(bad)!=0;assert bad.stat().st_mode & 0o777==0o755
 link=root/'link';link.symlink_to(fresh);assert check(link)!=0
 dangling=root/'dangling';dangling.symlink_to(root/'nonexistent');assert check(dangling)!=0;assert not (root/'nonexistent').exists()
 file=root/'file';file.write_text('keep');assert check(file)!=0 and file.read_text()=='keep'
print('FIRST_RUN_PRIVATE_STATE=PASS')
