from pathlib import Path
import os
import shutil
import subprocess

root = Path(__file__).resolve().parent
jdk = Path(os.environ['JAVA_HOME']) / 'bin' if os.environ.get('JAVA_HOME') else Path(shutil.which('java')).parent
out = root / 'build/callback-tests'
out.mkdir(parents=True, exist_ok=True)
subprocess.run([str(jdk / 'javac'), '-d', str(out),
                str(root / 'src/local/gt8pro/moseybridge/ReceiveCallbackCache.java'),
                str(root / 'tests/ReceiveCallbackCacheTest.java')], check=True)
subprocess.run([str(jdk / 'java'), '-cp', str(out),
                'local.gt8pro.moseybridge.ReceiveCallbackCacheTest'], check=True)
