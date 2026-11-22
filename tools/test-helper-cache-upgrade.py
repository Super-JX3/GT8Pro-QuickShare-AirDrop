"""Exercise the watcher startup checks with stale helper caches."""

import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile


PAYLOAD = Path(__file__).resolve().parents[1] / 'module-template/payload'
NOTICE = b'# Modified for the GT8 Pro adaptation; removed verbatim during assembly.\n'
APK_PATH = '/data/app/bridge-fixture/base.apk'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def assembled(name):
    return (PAYLOAD / name).read_bytes().replace(NOTICE, b'', 1)


watcher = assembled('watch-daily.sh').decode()
helper = assembled('check-helper.sh').decode()
startup, boundary, _ = watcher.partition('\n. "$d/bind-common.sh"')
assert boundary, 'Watcher startup checks must run before loading bind-common.sh'
helper_digest = digest(helper.encode())
assert f"'check-helper.sh:{helper_digest}'" in startup
pins = re.findall(r"'([\w-]+\.sh):([0-9a-f]{64})'", startup)
assert pins
for name, expected in pins:
    assert digest(assembled(name)) == expected, name

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp).resolve()
    cache = root / 'gt8pro-mosey-bridge'
    cache.mkdir(mode=0o700)
    cached_jar = cache / 'activation-helper.jar'
    bin_dir = root / 'bin'
    bin_dir.mkdir()
    apk = root / 'base.apk'
    apk.write_bytes(b'bridge APK fixture')
    shim = bin_dir / 'android-command'
    shim.write_text('''#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import stat
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
if command == 'id' and args == ['-u']:
    print(0)
elif command == 'cat' and args == ['/proc/self/attr/current']:
    print('u:r:ksu:s0')
elif command == 'getprop':
    print({'ro.product.model': 'RMX5200',
           'ro.build.display.id': 'RMX5200_16.0.10.501(CN01)'}[args[0]])
elif command == 'readlink' and args[0] == '-f':
    print(Path(args[1]).resolve())
elif command == 'stat' and args[:2] == ['-c', '%u:%a']:
    info = Path(args[2]).stat()
    assert info.st_uid == os.getuid()
    print(f'0:{stat.S_IMODE(info.st_mode):o}')
elif command == 'sha256sum' and len(args) == 1:
    path = os.environ['FIXTURE_APK'] if args[0] == os.environ['APK_PATH'] else args[0]
    print(hashlib.sha256(Path(path).read_bytes()).hexdigest(), args[0])
elif command == 'timeout' and args == [
        '-k', '1', '5', 'pm', 'path', '--user', '0', 'local.gt8pro.moseybridge']:
    print('package:' + os.environ['APK_PATH'])
elif command == 'timeout' and args[3:6] == [
        '/system/bin/app_process', '/system/bin', 'GT8ProLSPosedSetup']:
    assert args[-1] == os.environ['APK_PATH']
    assert os.environ['CLASSPATH'] == os.environ['EXPECTED_JAR']
    print('EXTRA_SCOPES=0')
    print('LSPOSED_BRIDGE_STATE modern enabled=1 scopes=2 apkMatches=1')
else:
    sys.exit(f'Unexpected fixture command: {command} {args}')
''')
    shim.chmod(0o700)
    for name in ('id', 'cat', 'getprop', 'readlink', 'stat', 'sha256sum', 'timeout'):
        (bin_dir / name).symlink_to(shim)
    env = {
        **os.environ,
        'PATH': f'{bin_dir}{os.pathsep}{os.environ["PATH"]}',
        'FIXTURE_APK': str(apk),
        'APK_PATH': APK_PATH,
    }

    def host_script(script):
        return (script.replace('PATH=/system/bin:/system/xbin\n', '', 1)
                .replace('/data/adb/gt8pro-mosey-daily', str(root / 'daily'))
                .replace('/data/adb/gt8pro-mosey-bridge', str(cache)))

    def prepare_runtime(jar_bytes):
        runtime = root / 'daily' / ('runtime-integrated-' + digest(jar_bytes))
        runtime.mkdir(parents=True, mode=0o700)
        jar = runtime / 'activation-helper.jar'
        jar.write_bytes(jar_bytes)
        jar.chmod(0o600)
        for name, _ in pins:
            path = runtime / name
            path.write_bytes(assembled(name))
            path.chmod(0o600)
        checker = runtime / 'check-helper.sh'
        fixture = host_script(helper)
        for variable, content in [('helper', jar_bytes), ('apk', apk.read_bytes())]:
            pattern = (rf'(sum=\$\(sha256sum "\${variable}"\) \|\| exit 1\n'
                       r'\[ "\$\{sum%% \*\}" = )[0-9a-f]{64}')
            fixture, count = re.subn(pattern, lambda match: match[1] + digest(content), fixture)
            assert count == 1, variable
        checker.write_text(fixture)
        return jar, digest(checker.read_bytes())

    def check_startup(jar, checker_digest):
        script = host_script(startup).replace(helper_digest, checker_digest)
        return subprocess.run(
            ['sh', '-c', script + '\nprintf "WATCH_STARTUP_CHECKS=PASS\\n"\n'],
            env={**env, 'GT8_RUNTIME_DIR': str(jar.parent), 'EXPECTED_JAR': str(jar)},
            capture_output=True, text=True, timeout=15,
        )

    old_jar, old_checker = prepare_runtime(b'original activation helper')
    new_jar, new_checker = prepare_runtime(b'rebuilt activation helper')
    first_boot = check_startup(old_jar, old_checker)
    assert first_boot.returncode == 0 and 'WATCH_STARTUP_CHECKS=PASS' in first_boot.stdout, first_boot
    assert not cached_jar.exists()
    for old_cache in (old_jar.read_bytes(), b'interrupted copy'):
        cached_jar.write_bytes(old_cache)
        cached_jar.chmod(0o600)
        result = check_startup(new_jar, new_checker)
        assert result.returncode == 0 and 'WATCH_STARTUP_CHECKS=PASS' in result.stdout, result
        assert cached_jar.read_bytes() == old_cache

    new_jar.chmod(0o644)
    assert check_startup(new_jar, new_checker).returncode != 0
    new_jar.chmod(0o600)
    new_jar.write_bytes(b'tampered runtime helper')
    assert check_startup(new_jar, new_checker).returncode != 0
    new_jar.unlink()
    cached_jar.write_bytes(b'rebuilt activation helper')
    new_jar.symlink_to(cached_jar)
    assert check_startup(new_jar, new_checker).returncode != 0

print('WATCHER_STARTUP_AFTER_HELPER_CACHE_UPGRADE=PASS')
