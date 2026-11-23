#!/usr/bin/env python3
"""Verify the APKs named in an explicit bridge build manifest."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import zipfile

from sdk_tools import extract_verified_sdk


PACKAGE = 'local.gt8pro.moseybridge'
DEX_PACKAGE = 'Llocal/gt8pro/moseybridge/'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_build(manifest):
    try:
        receipt = json.loads(manifest.read_text(encoding='utf-8'))
    except FileNotFoundError:
        raise ValueError(f'Build manifest not found: {manifest}') from None
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise ValueError(f'Invalid build manifest {manifest}: {error}') from error

    require(isinstance(receipt, dict), 'Build manifest must be a JSON object')
    require(receipt.get('package') == PACKAGE, f'Build manifest package must be {PACKAGE}')
    version = receipt.get('version')
    require(isinstance(version, str) and version.strip(), 'Build manifest is missing a valid version')
    version_code = receipt.get('versionCode')
    require(type(version_code) is int and version_code > 0,
            'Build manifest is missing a valid versionCode')
    files = receipt.get('files')
    require(isinstance(files, list) and files, 'Build manifest lists no APKs')

    apks = {}
    for item in files:
        require(isinstance(item, dict), 'Build manifest file entries must be JSON objects')
        name = item.get('file')
        require(isinstance(name, str) and name.endswith('.apk') and Path(name).name == name,
                'Each build manifest entry must name an APK next to the manifest')
        require(name not in apks, f'{name}: duplicate APK in build manifest')
        mode = item.get('mode')
        require(isinstance(mode, str) and mode.strip(), f'{name}: missing or invalid mode')
        require(type(item.get('nativeLookupAdapter')) is bool
                and type(item.get('gmsFalseToTrue')) is bool, f'{name}: invalid build variant flags')
        require(item.get('deviceTested') is False, f'{name}: expected a local build receipt')
        expected = item.get('sha256')
        require(isinstance(expected, str) and re.fullmatch(r'[0-9a-fA-F]{64}', expected),
                f'{name}: missing or invalid SHA-256')
        apk = manifest.parent / name
        try:
            data = apk.read_bytes()
        except FileNotFoundError:
            raise ValueError(f'APK listed in build manifest not found: {apk}') from None
        actual = hashlib.sha256(data).hexdigest()
        require(actual == expected.lower(), f'{name}: SHA-256 mismatch (expected {expected}, found {actual})')
        require(not apk.with_name(name + '.idsig').exists(), f'{name}: unexpected v4 signature sidecar')
        apks[name] = (item, data)
    return version, version_code, apks


def verify_zip(data):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        require(archive.testzip() is None, 'APK ZIP integrity check failed')
        names = archive.namelist()
        require(len(names) == len(set(names)), 'APK contains duplicate ZIP entries')
        require(archive.read('assets/xposed_init') == b'local.gt8pro.moseybridge.BridgeEntry\n',
                'Unexpected Xposed entry point')
        require(not any(name.startswith('lib/') or name.endswith(('.so', '.sh')) for name in names),
                'APK contains a native library or shell script')
        return archive.read('classes.dex')


def verify_dex(dex, item):
    require(dex[:8] in (b'dex\n039\0', b'dex\n040\0'), 'Unsupported classes.dex format')

    def u4(offset):
        return struct.unpack_from('<I', dex, offset)[0]

    def uleb(offset):
        value = 0
        for shift in range(0, 35, 7):
            byte = dex[offset]
            offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value, offset
        raise ValueError('Invalid ULEB128 value in classes.dex')

    require(u4(32) == len(dex), 'Invalid classes.dex length')
    strings = []
    count, offset = u4(56), u4(60)
    for index in range(count):
        _, start = uleb(u4(offset + 4 * index))
        strings.append(dex[start:dex.index(0, start)].decode('utf-8'))
    types = [strings[u4(u4(68) + 4 * index)] for index in range(u4(64))]
    classes = [u4(100) + 32 * index for index in range(u4(96))]
    names = [types[u4(offset)] for offset in classes]
    require(names and all(name.startswith(DEX_PACKAGE) for name in names),
            'Unexpected class outside the bridge package')
    variant = DEX_PACKAGE + 'BuildVariant;'
    require(variant in names, 'Missing BuildVariant class')
    build = classes[names.index(variant)]

    offset = u4(build + 24)
    static_count, offset = uleb(offset)
    for _ in range(3):
        _, offset = uleb(offset)
    fields = []
    index = 0
    for _ in range(static_count):
        delta, offset = uleb(offset)
        _, offset = uleb(offset)
        index += delta
        fields.append(strings[u4(u4(84) + 8 * index + 4)])
    offset = u4(build + 28)
    count, offset = uleb(offset)
    values = []
    for _ in range(count):
        byte = dex[offset]
        offset += 1
        kind, arg = byte & 31, byte >> 5
        if kind == 31:
            value = bool(arg)
        elif kind == 23:
            value = strings[int.from_bytes(dex[offset:offset + arg + 1], 'little')]
            offset += arg + 1
        else:
            raise ValueError('Unexpected constant in BuildVariant')
        values.append(value)

    actual = dict(zip(fields, values))
    expected = {'BINDER': item['nativeLookupAdapter'], 'GMS': item['gmsFalseToTrue'],
                'MODE': item['mode'], 'ROUTE': True}
    require(actual == expected, f'Build variant mismatch (expected {expected}, found {actual})')
    return len(classes), actual


def verify_android_manifest(aapt, apk, version, version_code, mode):
    badging = subprocess.run([aapt, 'dump', 'badging', apk], check=True,
                             capture_output=True, text=True).stdout
    package_line = next((line for line in badging.splitlines() if line.startswith('package: ')), '')
    fields = dict(re.findall(r"([A-Za-z]+)='([^']*)'", package_line))
    expected = {'name': PACKAGE, 'versionCode': str(version_code), 'versionName': f'{version}-{mode}'}
    for field, value in expected.items():
        actual = fields.get(field)
        require(actual == value, f'{field} mismatch (expected {value!r}, found {actual!r})')
    require("minSdkVersion:'36'" in badging and "targetSdkVersion:'36'" in badging,
            'Unexpected Android SDK requirements')
    require('uses-permission' not in badging, 'APK requests an unexpected permission')

    xml = subprocess.run([aapt, 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml'],
                         capture_output=True, text=True, check=True).stdout
    components = []
    current = None
    level = 0
    for line in xml.splitlines():
        indent = len(line) - len(line.lstrip())
        component = re.match(r'\s*E: (activity|provider) \(', line)
        if component:
            current = {'kind': component[1]}
            components.append(current)
            level = indent
            continue
        if current is not None and line.strip() and indent <= level:
            current = None
        if current is not None and indent == level + 2:
            attribute = re.search(r'android:(name|authorities|exported|grantUriPermissions)\([^)]*\)=(.*)$', line)
            if attribute:
                current[attribute[1]] = attribute[2].split(' (Raw:', 1)[0].strip('"')

    activities = [item for item in components if item['kind'] == 'activity']
    require(len(activities) == 2 and {item.get('name') for item in activities}
            == {'.MainActivity', '.ShareProbeActivity'}, 'Unexpected APK activities')
    require(all(item.get('exported') == 'true' for item in activities),
            'Expected both bridge activities to be exported')
    providers = [item for item in components if item['kind'] == 'provider']
    require(providers == [{'kind': 'provider', 'name': '.FixtureProvider', 'exported': 'false',
                           'grantUriPermissions': 'true',
                           'authorities': PACKAGE + '.fixture'}], 'Unexpected APK provider')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True, type=Path, help='Provenance JSON from this bridge build')
    parser.add_argument('--tools', type=Path, default=os.environ.get('GT8_ANDROID_TOOLS') or None,
                        help='Directory with the pinned SDK archives (or set GT8_ANDROID_TOOLS)')
    args = parser.parse_args()

    try:
        version, version_code, apks = load_build(args.manifest)
        if args.tools is None:
            parser.error('provide --tools or set GT8_ANDROID_TOOLS')
        with tempfile.TemporaryDirectory(prefix='gt8-verify-sdk-') as directory:
            stage = Path(directory)
            sdk = extract_verified_sdk(args.tools, stage / 'sdk')
            for name, (item, data) in apks.items():
                # Inspect the same bytes that passed the manifest hash check.
                apk = stage / name
                apk.write_bytes(data)
                try:
                    classes, flags = verify_dex(verify_zip(data), item)
                    verify_android_manifest(sdk / 'android-16/aapt2', apk, version, version_code, item['mode'])
                except (ValueError, zipfile.BadZipFile, KeyError, IndexError, struct.error,
                        subprocess.SubprocessError) as error:
                    raise ValueError(f'{name}: {error}') from error
                print('APK_VERIFIED', item['mode'], f'classes={classes}', f'flags={flags}')
    except (OSError, ValueError) as error:
        parser.exit(1, f'APK verification failed: {error}\n')
    print('APK_STRUCTURE_CHECKS_PASS')
    print('APK_TARGET_CLASSES_EXECUTED=false')


if __name__ == '__main__':
    main()
