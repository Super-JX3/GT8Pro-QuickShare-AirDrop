#!/usr/bin/env python3
"""Assemble the exact candidate using separately supplied, hash-pinned inputs."""
import argparse
import hashlib
import json
import shutil
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
digest = lambda data: hashlib.sha256(data).hexdigest()
NOTICE = b'# Modified for the GT8 Pro adaptation; removed verbatim during assembly.\n'
C_NOTICE = b'/* Modified for the GT8 Pro adaptation; removed verbatim during assembly. */\n'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', action='append', required=True, type=Path,
                        help='Local directory or ZIP containing required files; repeatable')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    spec = json.loads((ROOT / 'external-inputs.json').read_text())['files']
    wanted = {item['sha256']: item['size'] for item in spec}
    found = {}

    def accept(data):
        if len(data) > 32 * 1024 * 1024:
            return
        h = digest(data)
        if h in wanted and len(data) == wanted[h]:
            found[h] = data

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
                    if not item.is_dir() and item.file_size in wanted.values() and not item.flag_bits & 1:
                        accept(archive.read(item))
        elif source.is_file():
            accept(source.read_bytes())
        else:
            raise SystemExit('Input not found: ' + str(source))

    missing = [item for item in spec if item['sha256'] not in found]
    if missing:
        for item in missing:
            print('MISSING', item['sha256'], item['path'])
        raise SystemExit('Missing verified local inputs; no package produced')

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        stage = Path(tmp) / 'module'
        shutil.copytree(ROOT / 'module-template', stage, symlinks=False)
        # The public source carries modification notices. Strip only this exact
        # line when reconstructing the byte-pinned, previously built module.
        for path in stage.rglob('*'):
            if path.is_file() and (path.suffix in ('.sh', '.awk', '.c') or path.name in ('update-binary', 'sepolicy.rule')):
                data = path.read_bytes()
                marker = C_NOTICE if path.suffix == '.c' else NOTICE
                if data.count(marker) != 1:
                    raise SystemExit('Missing or duplicate source notice: ' + str(path.relative_to(stage)))
                path.write_bytes(data.replace(marker, b'', 1))
        for item in spec:
            rel = PurePosixPath(item['path'])
            if rel.is_absolute() or '..' in rel.parts:
                raise SystemExit('Invalid manifest path')
            out = stage.joinpath(*rel.parts)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(found[item['sha256']])
        manifest = stage / 'install.sha256'
        for line in manifest.read_text().splitlines():
            expected, rel = line.split(maxsplit=1)
            path = PurePosixPath(rel.lstrip('*'))
            if path.is_absolute() or '..' in path.parts or digest(stage.joinpath(*path.parts).read_bytes()) != expected:
                raise SystemExit('Installation manifest mismatch: ' + rel)
        if digest(manifest.read_bytes()) not in (stage / 'customize.sh').read_text():
            raise SystemExit('Installer manifest hash mismatch')
        with zipfile.ZipFile(args.output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(p for p in stage.rglob('*') if p.is_file()):
                info = zipfile.ZipInfo.from_file(path, path.relative_to(stage).as_posix())
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (0o100755 if path.name in ('update-binary', 'service.sh') else 0o100644) << 16
                archive.writestr(info, path.read_bytes())
        with zipfile.ZipFile(args.output) as archive:
            if archive.testzip() is not None:
                raise SystemExit('ZIP verification failed')
    print('PACKAGE=' + str(args.output))
    print('SHA256=' + digest(args.output.read_bytes()))

if __name__ == '__main__':
    main()
