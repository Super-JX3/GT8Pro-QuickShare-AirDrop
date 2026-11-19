#!/usr/bin/env python3
from pathlib import Path
import argparse,subprocess,json,hashlib
root=Path(__file__).resolve().parent.parent/'native'
p=argparse.ArgumentParser();p.add_argument('--clang',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
out=a.output.resolve();out.mkdir(parents=True,exist_ok=True);probe=root/'load-probe';compat=root/'registration-compat'
flags=['--target=aarch64-linux-android35','-std=c11','-Oz','-Wall','-Wextra','-Werror','-Wconversion','-Wshadow','-Wpedantic','-fstack-protector-strong','-D_FORTIFY_SOURCE=2','-fvisibility=hidden','-mbranch-protection=standard','-Wl,-z,relro,-z,now,-z,noexecstack','-Wl,--build-id=sha1',f'-ffile-prefix-map={root}=.','-Wl,-z,max-page-size=16384']
commands=[[*flags,'-fPIE','-pie',str(probe/'probe.c'),str(probe/'probe_parse.c'),'-ldl','-o',str(out/'mosey_load_probe')],[*flags,'-fPIC','-shared',str(probe/'marker.c'),'-Wl,-soname,libmosey_load_probe.so','-o',str(out/'libmosey_load_probe.so')],[*flags,'-fPIC','-shared',str(compat/'compat.c'),str(compat/'identity.c'),str(probe/'probe_parse.c'),'-I',str(probe),'-ldl','-Wl,-soname,libmosey_registration_compat.so','-Wl,--version-script='+str(compat/'exports.map'),'-Wl,--no-undefined','-o',str(out/'libmosey_registration_compat.so')]]
for args in commands:subprocess.run([str(a.clang),*args],check=True,timeout=120)
manifest={}
for f in (out/'mosey_load_probe',out/'libmosey_load_probe.so',out/'libmosey_registration_compat.so'):
 data=f.read_bytes();assert data[:6]==b'\x7fELF\x02\x01' and int.from_bytes(data[18:20],'little')==183;manifest[f.name]={'sha256':hashlib.sha256(data).hexdigest(),'size':len(data)}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print('NATIVE_COMPONENTS_BUILT=3')
