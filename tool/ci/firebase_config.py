"""Firebase configuration for distributable builds: written, never committed.

Each GitHub environment (``ios-development``, ``ios-staging``, ``ios-production``,
``android-development``, ``android-production``) holds the *client* configuration
of its own Firebase project under the same names:

  FIREBASE_CONFIG_BASE64   variable  base64 of google-services.json / GoogleService-Info.plist
  FIREBASE_PROJECT_ID      variable  project ID of that environment's Firebase project

plus one repository variable, the guard that keeps environments apart:

  FIREBASE_PRODUCTION_PROJECT_ID     project ID of OrangeOne Production

These are project identifiers that ship inside every app, not credentials. Private
service-account keys are never handled here (see upload_flutter_symbols.py).

Rules: the production flavor must use the production project; development and
staging must use a project that is *not* the production one. A mismatch fails the
build before anything is distributed.

Commands (a failure prints a fixed reason, never file contents):

  export  <android|ios> <flavor>   validate FIREBASE_CONFIG_BASE64 and append
                                   config/project_id to $GITHUB_OUTPUT (the
                                   allocate/environment job hands it to the
                                   credential-free build job)
  write   <android|ios> <flavor>   validate it and write the platform file
  verify-ios <app-or-archive> <flavor>
  verify-android <apk> <flavor>    check the finished artifact
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

# flavor -> Android applicationId
ANDROID_PACKAGES = {
    'development': 'com.orangeone.app.dev',
    'staging': 'com.orangeone.app.stg',
    'production': 'com.orangeone.app',
}


class ConfigError(ValueError):
    """A safe, fixed-text failure."""


def expected_project(flavor, environ=None):
    """(project of this environment, production project), already cross-checked."""
    environ = os.environ if environ is None else environ
    if flavor not in ANDROID_PACKAGES:
        raise ConfigError('Unknown flavor.')
    project = environ.get('FIREBASE_PROJECT_ID', '').strip()
    production = environ.get('FIREBASE_PRODUCTION_PROJECT_ID', '').strip()
    for name, value in (('FIREBASE_PROJECT_ID', project), ('FIREBASE_PRODUCTION_PROJECT_ID', production)):
        if not value:
            raise ConfigError(f'{name} is not set.')
    if flavor == 'production' and project != production:
        raise ConfigError('The production flavor must use the production Firebase project.')
    if flavor != 'production' and project == production:
        raise ConfigError(f'The {flavor} flavor must not use the production Firebase project.')
    return project, production


def parse_android(data, flavor, project):
    try:
        document = json.loads(data)
        found = document['project_info']['project_id']
        clients = document['client']
    except (ValueError, KeyError, TypeError):
        raise ConfigError('google-services.json is not valid.') from None
    if found != project:
        raise ConfigError(f'google-services.json is for another Firebase project than the {flavor} environment uses.')
    package = ANDROID_PACKAGES[flavor]
    for client in clients if isinstance(clients, list) else []:
        info = client.get('client_info', {}) if isinstance(client, dict) else {}
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
        raise ConfigError(f'GoogleService-Info.plist is for another Firebase project than the {flavor} environment uses.')
    if bundle != IOS_BUNDLE_ID:
        raise ConfigError('GoogleService-Info.plist must use the App Store bundle ID.')
    if not app_id or not key:
        raise ConfigError('GoogleService-Info.plist is incomplete.')
    return values


def validated(platform, flavor, environ=None):
    """The decoded, validated configuration bytes of this environment."""
    environ = os.environ if environ is None else environ
    project, _ = expected_project(flavor, environ)
    encoded = ''.join(environ.get('FIREBASE_CONFIG_BASE64', '').split())
    if not encoded:
        raise ConfigError(f'FIREBASE_CONFIG_BASE64 is not set for the {platform} {flavor} environment.')
    try:
        data = base64.b64decode(encoded, validate=True)
    except ValueError:
        raise ConfigError('FIREBASE_CONFIG_BASE64 is not valid base64.') from None
    if platform == 'android':
        parse_android(data, flavor, project)
    elif platform == 'ios':
        parse_ios(data, flavor, project)
    else:
        raise ConfigError('Unknown platform.')
    return data, project


def destination(platform, flavor, root=ROOT):
    if platform == 'android':
        return Path(root) / 'android/app/src' / flavor / 'google-services.json'
    if platform == 'ios':
        return Path(root) / 'ios/config' / flavor / 'GoogleService-Info.plist'
    raise ConfigError('Unknown platform.')


def write(platform, flavor, environ=None, root=ROOT):
    data, _ = validated(platform, flavor, environ)
    target = destination(platform, flavor, root)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    target.chmod(0o600)
    return target


def export(platform, flavor, environ=None):
    """Validated single-line base64 and project ID, for a job output."""
    data, project = validated(platform, flavor, environ)
    return base64.b64encode(data).decode('ascii'), project


def verify_ios(path, flavor, environ=None):
    """The built app (or archive) carries its environment's GoogleService-Info.plist."""
    project, _ = expected_project(flavor, environ)
    path = Path(path)
    app = path / 'Products/Applications/Runner.app' if (path / 'Products').is_dir() else path
    plist = app / 'GoogleService-Info.plist'
    if not plist.is_file():
        raise ConfigError('The build does not contain GoogleService-Info.plist.')
    parse_ios(plist.read_bytes(), flavor, project)


def verify_android(apk, flavor, environ=None):
    """The APK's resources name this environment's project; non-production builds
    must not contain the production project."""
    project, production = expected_project(flavor, environ)
    try:
        with zipfile.ZipFile(apk) as archive:
            resources = archive.read('resources.arsc')
    except (OSError, KeyError, zipfile.BadZipFile):
        raise ConfigError('The APK has no resources to check.') from None

    def contains(value):
        return value.encode('utf-8') in resources or value.encode('utf-16-le') in resources

    if not contains(project):
        raise ConfigError('The APK does not contain the Firebase configuration of its environment.')
    if project != production and contains(production):
        raise ConfigError('The APK contains the production Firebase project.')


def main(arguments=None, environ=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    environ = os.environ if environ is None else environ
    try:
        command = arguments[0]
        if command in ('write', 'export') and len(arguments) == 3:
            platform, flavor = arguments[1], arguments[2]
            if command == 'write':
                write(platform, flavor, environ)
                print(f'Firebase {platform} configuration for {flavor} written.')
            else:
                config, project = export(platform, flavor, environ)
                with open(environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as stream:
                    stream.write(f'config={config}\nproject_id={project}\n')
                print(f'Firebase {platform} configuration for {flavor} validated.')
        elif command == 'verify-ios' and len(arguments) == 3:
            verify_ios(arguments[1], arguments[2], environ)
            print(f'Firebase configuration verified for {arguments[2]}.')
        elif command == 'verify-android' and len(arguments) == 3:
            verify_android(arguments[1], arguments[2], environ)
            print(f'Firebase configuration verified for {arguments[2]}.')
        else:
            raise ConfigError('Usage: firebase_config.py write|export|verify-ios|verify-android ...')
    except ConfigError as error:
        print(f'Firebase configuration check failed: {error}', file=sys.stderr)
        return 1
    except (OSError, IndexError, KeyError):
        print('Firebase configuration check failed.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
