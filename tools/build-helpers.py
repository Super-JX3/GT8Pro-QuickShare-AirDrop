#!/usr/bin/env python3
"""Build project-owned helpers locally; this does not assemble an installable module."""
import argparse
import hashlib
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--android-jar', required=True, type=Path)
    ap.add_argument('--d8-jar', required=True, type=Path)
    ap.add_argument('--ndk-clang', required=True, type=Path)
    ap.add_argument('--jdk-bin', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    a = ap.parse_args()
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    def run(args):
        subprocess.run([str(v) for v in args], check=True, timeout=120)
    with tempfile.TemporaryDirectory() as td:
        stage = Path(td)
        for java, result in [('GT8ProLSPosedSetup', 'activation-helper.jar'),
                             ('GT8ProMosey60715Profile', 'profile-helper.jar')]:
            work = stage / java
            classes, dex = work / 'classes', work / 'dex'
            classes.mkdir(parents=True); dex.mkdir()
            run([a.jdk_bin/'javac', '-source', '17', '-target', '17', '-encoding', 'UTF-8',
                 '-cp', a.android_jar, '-d', classes, ROOT/'helpers'/(java+'.java')])
            jar = work/'classes.jar'
            with zipfile.ZipFile(jar, 'w') as z:
                for path in sorted(classes.rglob('*.class')):
                    z.write(path, path.relative_to(classes).as_posix())
            run([a.jdk_bin/'java', '-cp', a.d8_jar, 'com.android.tools.r8.D8',
                 '--release', '--min-api', '36', '--lib', a.android_jar, '--output', dex, jar])
            with zipfile.ZipFile(out/result, 'w') as z:
                z.write(dex/'classes.dex', 'classes.dex')
        cflags = ['--target=aarch64-linux-android36', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2']
        for source, name, static in [
            ('module-template/base-service/source/watchdog.c', 'gt8_service_watchdog', False),
            ('native/inner/watchdog.c', 'gt8_service_watchdog_soak', True),
            ('native/outer/outer-watchdog.c', 'outer-watchdog', True),
        ]:
            run([a.ndk_clang, *cflags, *(['-static'] if static else []), ROOT/source, '-o', out/name])
    manifest = {}
    for name in ('activation-helper.jar', 'profile-helper.jar', 'gt8_service_watchdog',
                 'gt8_service_watchdog_soak', 'outer-watchdog'):
        data = (out/name).read_bytes()
        manifest[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}
    (out/'local-helper-sha256.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print('HELPERS_BUILT=' + str(out))
    print('NOT_INSTALLABLE: checksum chain must be regenerated and verified before packaging')


if __name__ == '__main__':
    main()
