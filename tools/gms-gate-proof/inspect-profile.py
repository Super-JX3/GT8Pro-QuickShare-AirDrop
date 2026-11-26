#!/usr/bin/env python3
"""Propose a bridge profile from a locally obtained, Google-signed GMS base APK."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'bridge'))
from sdk_tools import extract_verified_sdk

GOOGLE_SIGNER = '5f2391277b1dbd489000467e4c2fa6af802430080457dce2f618992e9dfb5402'


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as apk:
        for chunk in iter(lambda: apk.read(1024 * 1024), b''):
            sha.update(chunk)
    return sha.hexdigest()


def run(args, timeout=60):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, text=True, timeout=timeout).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path, help='Installed GMS base APK')
    parser.add_argument('--tools', type=Path, required=True, help='Locally pinned Android SDK inputs')
    parser.add_argument('--jdk', type=Path, required=True, help='JDK 17 bin directory')
    parser.add_argument('--dex-reader', type=Path,
                        default=HERE.parents[1] / 'mobile-builder/src/moseyPLK/client/GmsDexFile.java',
                        help='DEX reader source with the mobile builder scanning API')
    args = parser.parse_args()
    before = digest(args.apk)
    with tempfile.TemporaryDirectory(prefix='gt8-gms-profile-') as temp:
        work = Path(temp)
        sdk = extract_verified_sdk(args.tools, work / 'sdk') / 'android-16'
        java = args.jdk / 'java'
        details = run([java, '-jar', sdk / 'lib/apksigner.jar', 'verify', '--min-sdk-version', '36',
                       '--max-sdk-version', '36', '--print-certs', args.apk])
        certificates = re.findall(r'^Signer #\d+ certificate SHA-256 digest: (\w+)$', details, re.M)
        if certificates != [GOOGLE_SIGNER]:
            raise ValueError('GMS APK signer mismatch')
        badging = run([sdk / 'aapt2', 'dump', 'badging', args.apk])
        manifest = re.search(r"^package: name='com\.google\.android\.gms' versionCode='(\d+)'[^\n]*$",
                             badging, re.M)
        if manifest is None or re.search(r"\bsplit=", manifest[0]):
            raise ValueError('Expected the Google Play services base APK')
        classes = work / 'classes'
        classes.mkdir()
        run([args.jdk / 'javac', '-d', classes, args.dex_reader, HERE / 'ProfileProof.java'])
        members = run([java, '-Xmx256m', '-cp', classes, 'local.gt8pro.gmsscan.ProfileProof', args.apk],
                      timeout=120).split()
        if len(members) != 4 or any(not re.fullmatch(r'[\w.$]+', item, re.ASCII) for item in members):
            raise ValueError('Invalid DEX profile')
    if before != digest(args.apk):
        raise ValueError('APK changed during inspection')
    profile = dict(zip(('flagClass', 'flagGetter', 'homeFeaturesClass', 'interopField'), members))
    print(json.dumps({'versionCode': int(manifest[1]), 'apkHash': before, **profile}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        raise SystemExit(f'Unable to propose a GMS profile: {exc}') from None
