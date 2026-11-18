"""Uploads the Dart debug symbols of a build to its Firebase Crashlytics project.

``--split-debug-info`` removes Dart symbols from the binary; without these files
Crashlytics shows unreadable Flutter stack traces. The upload needs a Firebase
service account, so it runs only in jobs of a protected GitHub environment. The
app ID comes from the build's own Firebase configuration, which also fixes the
project. Without the service account the step reports a warning instead of
failing the delivery. Never prints the credential.

  upload_flutter_symbols.py <symbols-dir> <google-services.json|GoogleService-Info.plist>
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

FIREBASE_TOOLS = 'firebase-tools@15.32.1'


def app_id(config):
    data = Path(config).read_bytes()
    if Path(config).suffix == '.plist':
        return plistlib.loads(data)['GOOGLE_APP_ID']
    document = json.loads(data)
    return document['client'][0]['client_info']['mobilesdk_app_id']


def command(symbols, identifier):
    return ['npx', '--yes', FIREBASE_TOOLS, 'crashlytics:symbols:upload', f'--app={identifier}', str(symbols)]


def main(arguments=None, environ=None, run=subprocess.run):
    arguments = sys.argv[1:] if arguments is None else arguments
    environ = os.environ if environ is None else environ
    try:
        symbols, config = Path(arguments[0]), Path(arguments[1])
        if not symbols.is_dir() or not any(symbols.iterdir()):
            print('Crashlytics symbol upload failed: no Dart symbols were produced.', file=sys.stderr)
            return 1
        identifier = app_id(config)
    except (IndexError, OSError, KeyError, ValueError, plistlib.InvalidFileException):
        print('Crashlytics symbol upload failed: the symbols or Firebase configuration are missing.',
              file=sys.stderr)
        return 1
    account = environ.get('FIREBASE_SERVICE_ACCOUNT_JSON', '')
    if not account:
        print('::warning::FIREBASE_SERVICE_ACCOUNT_JSON is not set; Dart symbols were not uploaded, '
              'so Flutter stack traces of this build stay unsymbolicated.')
        return 0
    with tempfile.TemporaryDirectory() as folder:
        credentials = Path(folder) / 'credentials.json'
        credentials.write_text(account, encoding='utf-8')
        credentials.chmod(0o600)
        try:
            run(command(symbols, identifier), check=True, capture_output=True,
                env={**environ, 'GOOGLE_APPLICATION_CREDENTIALS': str(credentials)})
        except (OSError, subprocess.SubprocessError):
            # The tool's output may echo identifiers; report only the stage.
            print('Crashlytics symbol upload failed at stage: upload.', file=sys.stderr)
            return 1
    print('Dart symbols uploaded to Crashlytics.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
