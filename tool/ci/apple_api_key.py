"""Temporary App Store Connect API key for jobs that only call Apple's web API.

Platform independent (Linux and macOS runners): build-number allocation and
TestFlight group checks need the API key but no keychain, certificate or Xcode.
Certificates, profiles and keychains stay in ios_signing.py (macOS only).
Never print secrets or subprocess commands.
"""
import base64
import os
from pathlib import Path
import shutil
import subprocess
import sys

_failure_stage = 'startup'


def _stage(name):
    global _failure_stage
    _failure_stage = name


def required(name):
    value = os.environ.get(name)
    if not value:
        raise ValueError('A required setting is missing: ' + name)
    return value


def folder():
    # Same folder as ios_signing.py, so either script's cleanup removes the key.
    return Path(required('RUNNER_TEMP')) / 'orangeone-signing'


def openssl():
    path = shutil.which('openssl')
    if not path:
        raise ValueError('openssl is not available on this runner.')
    return path


def install_api_key():
    _stage('api-key-decode')
    data = base64.b64decode(''.join(required('APP_STORE_CONNECT_KEY_BASE64').split()), validate=True)
    _stage('api-key-validation')
    root = folder()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = root / 'AuthKey.p8'
    path.write_bytes(data)
    path.chmod(0o600)
    subprocess.run((openssl(), 'pkey', '-in', str(path), '-noout'), check=True, capture_output=True)
    _stage('api-key-export')
    value = str(path)
    if '\n' in value or '\r' in value:
        raise ValueError('Invalid key path')
    with open(required('GITHUB_ENV'), 'a', encoding='utf-8') as stream:
        stream.write('APP_STORE_CONNECT_KEY_FILE=' + value + '\n')


def cleanup():
    _stage('cleanup')
    root = folder()
    if root.exists():
        shutil.rmtree(root)


def main(arguments=None):
    _stage('startup')
    try:
        operation = (sys.argv[1:] if arguments is None else arguments)[0]
        if operation == 'api-key':
            install_api_key()
        elif operation == 'cleanup':
            cleanup()
        else:
            raise ValueError('Unsupported Apple API operation')
    except Exception:
        # CLI security boundary: even unexpected exceptions may contain credentials.
        print('Apple API key operation failed at stage: ' + _failure_stage + '.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
