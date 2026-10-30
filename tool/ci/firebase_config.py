"""Firebase configuration for distributable builds: written, never committed.

CI stores the per-flavor ``google-services.json`` (Android) and
``GoogleService-Info.plist`` (iOS) as base64 repository variables named
``FIREBASE_<ANDROID|IOS>_<FLAVOR>_B64``. They hold
project identifiers that ship inside every app, not credentials, so they may be
read by the secret-free archive job. Private service-account keys are never
handled here.

Commands (failure prints a fixed reason, never file contents):

  write   <android|ios> <flavor>   validate the configuration in
                                   FIREBASE_<PLATFORM>_<FLAVOR>_B64 and write it
  verify-ios <app-or-archive> <flavor>
  verify-android <apk> <flavor>    check the finished artifact carries the
                                   Firebase project of its flavor

Project rule: development and staging report to the non-production Firebase
project, production to the production one, and the two must differ.
"""
import base64
import json
import os
from pathlib import Path
import plistlib
import sys
import zipfile

from release_flavors import BUNDLES

ROOT = Path(__file__).resolve().parents[2]
IOS_BUNDLE_ID = BUNDLES['production']

# flavor -> (Firebase project kind, Android applicationId)
FLAVORS = {
    'development': ('nonproduction', 'com.orangeone.app.dev'),
    'staging': ('nonproduction', 'com.orangeone.app.stg'),
    'production': ('production', 'com.orangeone.app'),
}
PROJECT_VARIABLES = {
    'nonproduction': 'FIREBASE_PROJECT_ID_NONPRODUCTION',
    'production': 'FIREBASE_PROJECT_ID_PRODUCTION',
}


class ConfigError(ValueError):
    """A safe, fixed-text failure."""


def expected_project(flavor, environ=None):
    environ = os.environ if environ is None else environ
    if flavor not in FLAVORS:
        raise ConfigError('Unknown flavor.')
    ids = {kind: environ.get(name, '').strip() for kind, name in PROJECT_VARIABLES.items()}
    for kind, value in ids.items():
        if not value:
            raise ConfigError(f'{PROJECT_VARIABLES[kind]} is not set.')
    if ids['nonproduction'] == ids['production']:
        raise ConfigError('Production and non-production must use different Firebase projects.')
    return ids[FLAVORS[flavor][0]], ids


def parse_android(data, flavor, project):
    try:
        document = json.loads(data)
        found = document['project_info']['project_id']
        clients = document['client']
    except (ValueError, KeyError, TypeError):
        raise ConfigError('google-services.json is not valid.') from None
    if found != project:
        raise ConfigError(f'google-services.json is for another Firebase project than the {flavor} flavor uses.')
    package = FLAVORS[flavor][1]
    for client in clients if isinstance(clients, list) else []:
        info = client.get('client_info', {})
        if info.get('android_client_info', {}).get('package_name') == package and info.get('mobilesdk_app_id'):
            return document
    raise ConfigError(f'google-services.json has no Android app for {package}.')


def parse_ios(data, flavor, project):
    try:
        values = plistlib.loads(data)
        found, bundle = values['PROJECT_ID'], values['BUNDLE_ID']
        app_id, key = values['GOOGLE_APP_ID'], values['API_KEY']
    except (ValueError, KeyError, TypeError, plistlib.InvalidFileException):
        raise ConfigError('GoogleService-Info.plist is not valid.') from None
    if found != project:
        raise ConfigError(f'GoogleService-Info.plist is for another Firebase project than the {flavor} flavor uses.')
    if bundle != IOS_BUNDLE_ID:
        raise ConfigError('GoogleService-Info.plist must use the App Store bundle ID.')
    if not app_id or not key:
        raise ConfigError('GoogleService-Info.plist is incomplete.')
    return values


def destination(platform, flavor, root=ROOT):
    if platform == 'android':
        return Path(root) / 'android/app/src' / flavor / 'google-services.json'
    if platform == 'ios':
        return Path(root) / 'ios/config' / flavor / 'GoogleService-Info.plist'
    raise ConfigError('Unknown platform.')


def write(platform, flavor, environ=None, root=ROOT):
    environ = os.environ if environ is None else environ
    project, _ = expected_project(flavor, environ)
    name = f'FIREBASE_{platform.upper()}_{flavor.upper()}_B64'
    encoded = ''.join(environ.get(name, '').split())
    if not encoded:
        raise ConfigError(f'{name} is not set.')
    try:
        data = base64.b64decode(encoded, validate=True)
    except ValueError:
        raise ConfigError('The Firebase configuration is not valid base64.') from None
    (parse_android if platform == 'android' else parse_ios)(data, flavor, project)
    target = destination(platform, flavor, root)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    target.chmod(0o600)
    return target


def verify_ios(path, flavor, environ=None):
    """The built app (or archive) carries its flavor's GoogleService-Info.plist."""
    project, _ = expected_project(flavor, environ)
    path = Path(path)
    app = path / 'Products/Applications/Runner.app' if (path / 'Products').is_dir() else path
    plist = app / 'GoogleService-Info.plist'
    if not plist.is_file():
        raise ConfigError('The build does not contain GoogleService-Info.plist.')
    parse_ios(plist.read_bytes(), flavor, project)


def verify_android(apk, flavor, environ=None):
    """The APK's resources name the flavor's Firebase project and no other."""
    project, ids = expected_project(flavor, environ)
    others = [value for value in ids.values() if value != project]
    try:
        with zipfile.ZipFile(apk) as archive:
            resources = archive.read('resources.arsc')
    except (OSError, KeyError, zipfile.BadZipFile):
        raise ConfigError('The APK has no resources to check.') from None

    def contains(value):
        return value.encode('utf-8') in resources or value.encode('utf-16-le') in resources

    if not contains(project):
        raise ConfigError('The APK does not contain the Firebase configuration of its flavor.')
    if any(contains(other) for other in others):
        raise ConfigError('The APK contains another environment\'s Firebase project.')


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    try:
        command = arguments[0]
        if command == 'write' and len(arguments) == 3:
            write(arguments[1], arguments[2])
            print(f'Firebase {arguments[1]} configuration for {arguments[2]} written.')
        elif command == 'verify-ios' and len(arguments) == 3:
            verify_ios(arguments[1], arguments[2])
            print(f'Firebase configuration verified for {arguments[2]}.')
        elif command == 'verify-android' and len(arguments) == 3:
            verify_android(arguments[1], arguments[2])
            print(f'Firebase configuration verified for {arguments[2]}.')
        else:
            raise ConfigError('Usage: firebase_config.py write|verify-ios|verify-android ...')
    except ConfigError as error:
        print(f'Firebase configuration check failed: {error}', file=sys.stderr)
        return 1
    except (OSError, IndexError):
        print('Firebase configuration check failed.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
