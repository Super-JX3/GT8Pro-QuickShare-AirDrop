"""Extract only the SDK files used by builds from the pinned macOS archives."""

import hashlib
import io
import zipfile


ARCHIVE_SHA1 = {
    'platform-36_r02.zip': '2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576',
    'build-tools_r36_macosx.zip': '199ae0047ee61e842f8ee0c6d3918e44fb9a1f83',
}
XPOSED_SHA256 = 'f48c635f1c7469fdec0e00ad2ea0b7a6b2f5b55065784a35b7ca3a84615e8e25'
SDK_MEMBERS = {
    'platform-36_r02.zip': ('android-36/android.jar',),
    'build-tools_r36_macosx.zip': (
        'android-16/aapt2',
        'android-16/zipalign',
        'android-16/lib/d8.jar',
        'android-16/lib/apksigner.jar',
        'android-16/lib64/libc++.dylib',
        'android-16/lib64/libc++.1.dylib',
        'android-16/lib64/libc++abi.1.dylib',
    ),
}


def verified_bytes(path, hash_function, expected):
    data = path.read_bytes()
    if hash_function(data).hexdigest() != expected:
        raise SystemExit('Build input checksum mismatch: ' + path.name)
    return data


def extract_verified_sdk(tools, destination):
    """Populate a new private directory, using the same bytes we verified."""
    destination.mkdir(mode=0o700)
    for name, expected in ARCHIVE_SHA1.items():
        data = verified_bytes(tools / name, hashlib.sha1, expected)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for member in SDK_MEMBERS[name]:
                target = destination / member
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(member))
                if target.name in ('aapt2', 'zipalign'):
                    target.chmod(0o700)
    xposed = verified_bytes(tools / 'api-82.jar', hashlib.sha256, XPOSED_SHA256)
    (destination / 'api-82.jar').write_bytes(xposed)
    return destination
