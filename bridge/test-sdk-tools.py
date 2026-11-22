"""Ensure builds consume the verified archive, even with a stale SDK tree."""

import hashlib
from pathlib import Path
import stat
import tempfile
from unittest.mock import patch
import zipfile

import sdk_tools


with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    tools = root / 'inputs'
    tools.mkdir()
    old_sdk = tools / 'sdk'
    (old_sdk / 'android-16/lib').mkdir(parents=True)
    stale_files = ['android-16/aapt2', 'android-16/lib/d8.jar']
    for member in stale_files:
        (old_sdk / member).write_bytes(b'previously extracted tool')
    archives = {}
    for name, members in sdk_tools.SDK_MEMBERS.items():
        path = tools / name
        with zipfile.ZipFile(path, 'w') as archive:
            for member in members:
                archive.writestr(member, member.encode())
        archives[name] = hashlib.sha1(path.read_bytes()).hexdigest()
    api = tools / 'api-82.jar'
    api.write_bytes(b'Xposed API fixture')

    with patch.dict(sdk_tools.ARCHIVE_SHA1, archives), patch.object(
        sdk_tools, 'XPOSED_SHA256', hashlib.sha256(api.read_bytes()).hexdigest()
    ):
        sdk = sdk_tools.extract_verified_sdk(tools, root / 'verified-sdk')
        for members in sdk_tools.SDK_MEMBERS.values():
            for member in members:
                assert (sdk / member).read_bytes() == member.encode(), member
        for member in stale_files:
            assert (old_sdk / member).read_bytes() == b'previously extracted tool'
        assert stat.S_IMODE((sdk / 'android-16/aapt2').stat().st_mode) == 0o700
        assert stat.S_IMODE((sdk / 'android-16/zipalign').stat().st_mode) == 0o700
        assert (sdk / api.name).read_bytes() == api.read_bytes()

        for name in (*archives, api.name):
            source = tools / name
            original = source.read_bytes()
            source.write_bytes(original + b'corrupt')
            try:
                sdk_tools.extract_verified_sdk(tools, root / ('bad-' + name))
            except SystemExit as error:
                assert str(error) == 'Build input checksum mismatch: ' + name
            else:
                raise AssertionError('Accepted a modified build input: ' + name)
            source.write_bytes(original)

print('PINNED_SDK_TOOLS_AND_TAMPER_REJECTION=PASS')
