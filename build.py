#!/usr/bin/env python3
"""Assemble the pinned experimental module from local, verified inputs."""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description='Build the 0.14.1 experimental module')
    parser.add_argument('--input', action='append', type=Path,
                        help='Locally obtained files, directory or ZIP; may be repeated')
    parser.add_argument('--output', type=Path, default=ROOT/'dist/GT8Pro-QuickShare-0.14.1.zip')
    args = parser.parse_args()
    inputs = args.input or [ROOT/'local-inputs']
    missing = [str(path) for path in inputs if not path.exists()]
    if missing:
        parser.error('Input not found: ' + ', '.join(missing)
                     + '; place authorized component files in local-inputs or pass --input')
    helpers = ROOT/'releases/GT8Pro-project-helpers-0.13.9.zip'
    if not helpers.is_file():
        parser.error('Project helper bundle is missing: ' + str(helpers))
    command = [sys.executable, str(ROOT/'tools/assemble.py'), '--input', str(helpers)]
    for path in inputs:
        command.extend(['--input', str(path)])
    command.extend(['--output', str(args.output)])
    return subprocess.call(command)


if __name__ == '__main__':
    raise SystemExit(main())
