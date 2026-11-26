from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent
src = root / 'src/local/gt8pro/builder'
tests = root / 'tests/local/gt8pro/builder'
profile = root.parent / 'bridge/src/local/gt8pro/moseybridge/GmsProfile.java'
with tempfile.TemporaryDirectory(prefix='gt8-builder-test-') as classes:
    subprocess.run(['javac', '-d', classes, profile, src / 'ModulePackage.java', src / 'Profiles.java',
                    tests / 'ModulePackageTest.java', tests / 'ProfilesTest.java'], check=True)
    for test in ('ModulePackageTest', 'ProfilesTest'):
        subprocess.run(['java', '-cp', classes, f'local.gt8pro.builder.{test}'], check=True)
