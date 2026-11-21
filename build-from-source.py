#!/usr/bin/env python3
"""Locally build project components and assemble a hash-verified candidate.

External vendor inputs remain byte-pinned. This tool does not use the network
and does not install the resulting artifacts on a device.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent
NOTICE = b'# Modified for the GT8 Pro adaptation; removed verbatim during assembly.\n'
C_NOTICE = b'/* Modified for the GT8 Pro adaptation; removed verbatim during assembly. */\n'
digest = lambda data: hashlib.sha256(data).hexdigest()

# These inputs are built locally. All remaining inputs are external and pinned.
OWN = {
    'base-service/tools/gt8_service_watchdog': 'gt8_service_watchdog',
    'payload/activation-helper.jar': 'activation-helper.jar',
    'payload/profile-helper.jar': 'profile-helper.jar',
    'payload/gt8_service_watchdog_soak': 'gt8_service_watchdog_soak',
    'payload/outer-watchdog': 'outer-watchdog',
    'base-service/system/odm/bin/mosey_load_probe': 'mosey_load_probe',
    'system/odm/bin/mosey_load_probe': 'mosey_load_probe',
    'base-service/system/odm/lib64/libmosey_load_probe.so': 'libmosey_load_probe.so',
    'system/odm/lib64/libmosey_load_probe.so': 'libmosey_load_probe.so',
    'base-service/system/odm/lib64/libmosey_registration_compat.so': 'libmosey_registration_compat.so',
    'system/odm/lib64/libmosey_registration_compat.so': 'libmosey_registration_compat.so',
}


def safe_relative(name):
    path = PurePosixPath(name.lstrip('*'))
    if path.is_absolute() or '..' in path.parts or not path.parts:
        raise SystemExit('Invalid manifest path: ' + name)
    return path


def verify_manifest(manifest, base):
    for line in manifest.read_text().splitlines():
        expected, name = line.split(maxsplit=1)
        path = base.joinpath(*safe_relative(name).parts)
        if not path.is_file() or path.is_symlink() or digest(path.read_bytes()) != expected:
            raise SystemExit('Manifest mismatch: ' + str(manifest.relative_to(base.parent)) + ' ' + name)


def verify_inventory(manifest, base, excluded):
    listed = {safe_relative(line.split(maxsplit=1)[1]).as_posix()
              for line in manifest.read_text().splitlines()}
    actual = {path.relative_to(base).as_posix() for path in base.rglob('*')
              if path.is_file() and path.relative_to(base).as_posix() not in excluded}
    if listed != actual:
        raise SystemExit('Manifest inventory mismatch: ' + str(manifest) +
                         ' unlisted=' + repr(sorted(actual-listed)) +
                         ' missing=' + repr(sorted(listed-actual)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tools', type=Path, required=True, help='Verified bridge SDK/tool archive directory')
    parser.add_argument('--jdk-bin', type=Path, required=True)
    parser.add_argument('--ndk-clang', type=Path, required=True)
    parser.add_argument('--signing', type=Path, required=True, help='Private signing directory, kept outside Git')
    parser.add_argument('--input', type=Path, action='append', required=True, help='Authorized external inputs; repeatable')
    parser.add_argument('--output', type=Path, default=ROOT/'dist/GT8Pro-source-build.zip')
    args = parser.parse_args()
    spec = json.loads((ROOT/'external-inputs.json').read_text())['files']
    if not OWN.keys() <= {entry['path'] for entry in spec}:
        raise SystemExit('Project component manifest does not match source builder')
    external = [entry for entry in spec if entry['path'] not in OWN]
    wanted = {entry['sha256']: entry['size'] for entry in external}
    found = {}

    def accept(data):
        if len(data) <= 32*1024*1024:
            sha = digest(data)
            if wanted.get(sha) == len(data):
                found[sha] = data

    for source in args.input:
        if source.is_symlink():
            raise SystemExit('Input must not be a symlink')
        if source.is_dir():
            for path in source.rglob('*'):
                if path.is_file() and not path.is_symlink() and path.stat().st_size in wanted.values():
                    accept(path.read_bytes())
        elif source.is_file() and zipfile.is_zipfile(source):
            with zipfile.ZipFile(source) as archive:
                for item in archive.infolist():
                    if not item.is_dir() and not item.flag_bits & 1 and item.file_size in wanted.values():
                        accept(archive.read(item))
        elif source.is_file():
            accept(source.read_bytes())
        else:
            raise SystemExit('Input not found: ' + str(source))
    missing = [entry for entry in external if entry['sha256'] not in found]
    if missing:
        for entry in missing:
            print('MISSING', entry['sha256'], entry['path'])
        raise SystemExit('Missing verified external inputs; no package produced')

    with tempfile.TemporaryDirectory() as td:
        temp = Path(td); stage = temp/'module'; built = temp/'built'; apkdir = temp/'bridge'
        subprocess.run([sys.executable, str(ROOT/'bridge/build.py'), '--tools', str(args.tools),
                        '--jdk', str(args.jdk_bin), '--out', str(apkdir), '--signing', str(args.signing)], check=True)
        subprocess.run([sys.executable, str(ROOT/'tools/build-helpers.py'),
                        '--android-jar', str(args.tools/'sdk/android-36/android.jar'),
                        '--d8-jar', str(args.tools/'sdk/android-16/lib/d8.jar'), '--ndk-clang', str(args.ndk_clang),
                        '--jdk-bin', str(args.jdk_bin), '--output', str(built)], check=True)
        subprocess.run([sys.executable, str(ROOT/'tools/build-upstream-native.py'),
                        '--clang', str(args.ndk_clang), '--output', str(built)], check=True)
        apks = list(apkdir.glob('GT8Pro-MoseyBridge-*-transfer-test.apk'))
        if len(apks) != 1:
            raise SystemExit('Bridge build did not produce exactly one transfer-test APK')
        new_apk = digest(apks[0].read_bytes())
        if any(p.is_symlink() for p in (ROOT/'module-template').rglob('*')):
            raise SystemExit('Module template must not contain symlinks')
        shutil.copytree(ROOT/'module-template', stage, symlinks=False)
        for path in stage.rglob('*'):
            if path.is_file() and (path.suffix in ('.sh','.awk','.c') or path.name in ('update-binary','sepolicy.rule')):
                data = path.read_bytes(); marker = C_NOTICE if path.suffix == '.c' else NOTICE
                if data.count(marker) != 1:
                    raise SystemExit('Missing or duplicate source notice: ' + str(path.relative_to(stage)))
                path.write_bytes(data.replace(marker,b'',1))
        baseline = {}
        for line in (stage/'install.sha256').read_text().splitlines():
            sha, name = line.split(maxsplit=1); baseline[safe_relative(name).as_posix()] = sha
        for entry in spec:
            path = stage.joinpath(*safe_relative(entry['path']).parts)
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes((built/OWN[entry['path']]).read_bytes() if entry['path'] in OWN else found[entry['sha256']])

        files = [p for p in stage.rglob('*') if p.is_file()]
        known = {p: baseline.get(p.relative_to(stage).as_posix(), digest(p.read_bytes())) for p in files}
        provenance = stage/'base-service/provenance.json'
        record = json.loads(provenance.read_text())
        record['originalWatchdog'] = record.pop('watchdog')
        record['localRebuild'] = {'deviceTested': False, 'bridgeSha256': new_apk,
                                  'components': {name: digest((built/name).read_bytes()) for name in sorted(set(OWN.values()))}}
        provenance.write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n')
        textual = []
        for path in files:
            if path.name == 'provenance.json' or path.suffix == '.xml':
                continue
            data = path.read_bytes()
            if b'\0' in data:
                continue
            try: data.decode('utf-8')
            except UnicodeDecodeError: continue
            textual.append(path)
        checker = stage/'payload/check-helper.sh'
        text = checker.read_text()
        # Read the installed APK pin from the checked-in checker. This also
        # supports local candidates that do not have a binary in releases/.
        pins = re.findall(
            r'^sum=\$\(sha256sum "\$apk"\) \|\| exit 1\n'
            r'\[ "\$\{sum%% \*\}" = ([0-9a-f]{64}) \] \|\| exit 1$',
            text, re.MULTILINE)
        if len(pins) != 1 or text.count(pins[0]) != 1:
            raise SystemExit('Expected bridge pin missing or ambiguous')
        checker.write_text(text.replace(pins[0], new_apk))
        for _ in range(80):
            current = {p:digest(p.read_bytes()) for p in files}; groups = {}
            for path in files:
                groups.setdefault(known[path],set()).add(current[path])
            if any(len(values) != 1 for values in groups.values()):
                raise SystemExit('Previously identical files now differ; cannot safely update hash references')
            changes = {old:next(iter(values)) for old,values in groups.items() if old != next(iter(values))}
            known = current
            if not changes: break
            for path in textual:
                content = path.read_text()
                for old,new in changes.items(): content = content.replace(old,new)
                path.write_text(content)
        else:
            raise SystemExit('Hash dependency graph did not converge')
        for manifest,base in [(stage/'install.sha256',stage), (stage/'payload.sha256',stage/'payload'),
                              (stage/'base-service/install.sha256',stage/'base-service'),
                              (stage/'base-service/payload.sha256',stage/'base-service'),
                              (stage/'base-app/install.sha256',stage/'base-app'),
                              (stage/'base-app/payload.sha256',stage/'base-app')]:
            verify_manifest(manifest,base)
        verify_inventory(stage/'install.sha256', stage,
                         {'install.sha256', 'customize.sh', 'META-INF/com/google/android/update-binary',
                          'META-INF/com/google/android/updater-script'})
        verify_inventory(stage/'payload.sha256', stage/'payload', set())
        if digest((stage/'install.sha256').read_bytes()) not in (stage/'customize.sh').read_text():
            raise SystemExit('Installer manifest pin mismatch')
        if digest((stage/'payload.sha256').read_bytes()) not in (stage/'service.sh').read_text():
            raise SystemExit('Runtime manifest pin mismatch')
        args.output.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED) as z:
            for path in sorted(p for p in stage.rglob('*') if p.is_file()):
                info=zipfile.ZipInfo.from_file(path,path.relative_to(stage).as_posix())
                info.compress_type=zipfile.ZIP_DEFLATED
                info.external_attr=(0o100755 if path.name in ('update-binary','service.sh') else 0o100644)<<16
                z.writestr(info,path.read_bytes())
        if zipfile.ZipFile(args.output).testzip() is not None:
            raise SystemExit('ZIP verification failed')
        apkout=args.output.with_suffix('.bridge.apk')
        shutil.copyfile(apks[0],apkout)
    print('MODULE='+str(args.output))
    print('MODULE_SHA256='+digest(args.output.read_bytes()))
    print('BRIDGE='+str(apkout))
    print('BRIDGE_SHA256='+digest(apkout.read_bytes()))
    print('DEVICE_TESTED=false')


if __name__ == '__main__':
    main()
