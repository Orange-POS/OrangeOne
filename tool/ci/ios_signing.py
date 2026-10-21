"""Ephemeral macOS signing material. Never print secrets or subprocess commands."""
import base64
import datetime as dt
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import hashlib
import zipfile
from release_flavors import bundle_id

def validate_profile(profile, team, now=None, flavor=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    entitlements = profile.get('Entitlements', {})
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    expiry = profile.get('ExpirationDate')
    if isinstance(expiry, dt.datetime) and expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=dt.timezone.utc)
    if (not re.fullmatch(r'[A-Z0-9]{10}', team)
            or team not in profile.get('TeamIdentifier', [])
            or len(prefixes) != 1
            or entitlements.get('application-identifier') != prefixes[0] + '.' + bundle_id(flavor)
            or entitlements.get('get-task-allow') is not False
            or profile.get('ProvisionedDevices') is not None
            or profile.get('ProvisionsAllDevices', False)
            or not isinstance(expiry, dt.datetime) or expiry <= now
            or not re.fullmatch(r'[A-Fa-f0-9-]{36}', profile.get('UUID', ''))
            or not profile.get('Name')
            or any(c in profile['Name'] for c in '\r\n')):
        raise ValueError('Use an unexpired App Store distribution profile for the selected bundle and team.')
    return profile['UUID'], profile['Name']


def validate_entitlements(entitlements, profile, team):
    """Current app requests only its own keychain group, never extra capabilities."""
    prefix = profile['ApplicationIdentifierPrefix'][0]
    expected = prefix + '.' + bundle_id()
    allowed = {'application-identifier', 'com.apple.developer.team-identifier',
               'keychain-access-groups', 'get-task-allow', 'beta-reports-active'}
    if not isinstance(entitlements, dict) or set(entitlements) - allowed:
        raise ValueError('Unsupported application entitlement.')
    for key, value in entitlements.items():
        if key == 'keychain-access-groups':
            grants = profile['Entitlements'].get(key, [])
            if value != [expected] or not any(g in (expected, prefix + '.*') for g in grants):
                raise ValueError('Profile does not grant the application keychain group.')
        elif key == 'application-identifier':
            if value != expected:
                raise ValueError('Wrong entitlement application identifier.')
        elif key == 'com.apple.developer.team-identifier':
            if value != team:
                raise ValueError('Wrong entitlement team.')
        elif value != profile['Entitlements'].get(key):
            raise ValueError('Entitlement is not granted by profile.')


def validate_certificate(profile, identities):
    certificates = profile.get('DeveloperCertificates', [])
    for cert in certificates:
        if isinstance(cert, bytes):
            fingerprint = hashlib.sha1(cert).hexdigest().upper()
            if fingerprint.encode() in identities.upper():
                return fingerprint
    raise ValueError('Imported distribution identity does not match the profile certificate.')


def verify_export(ipa):
    """Verify exported identity/profile and signed entitlements without running app code."""
    with zipfile.ZipFile(ipa) as archive:
        info = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
    if (info.get('CFBundleIdentifier') != bundle_id()
            or info.get('CFBundleShortVersionString') != required('RELEASE_VERSION')
            or info.get('CFBundleVersion') != required('RELEASE_BUILD_NUMBER')):
        raise ValueError('Exported IPA identity does not match release request.')
    destination = folder() / 'export-check'
    destination.mkdir(mode=0o700)
    run('/usr/bin/ditto', '-x', '-k', str(ipa), str(destination))
    app = destination / 'Payload/Runner.app'
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    profile = plistlib.loads(run('/usr/bin/security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')))
    uuid, _ = validate_profile(profile, required('APPLE_TEAM_ID'))
    if uuid != required('IOS_PROFILE_UUID'):
        raise ValueError('Export used a different provisioning profile.')
    entitlements = plistlib.loads(run('/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)))
    expected = profile['ApplicationIdentifierPrefix'][0] + '.' + bundle_id()
    if (entitlements.get('application-identifier') != expected
            or entitlements.get('com.apple.developer.team-identifier') != required('APPLE_TEAM_ID')
            or entitlements.get('get-task-allow', False) is not False):
        raise ValueError('Exported signing entitlements do not match release.')
    validate_entitlements(entitlements, profile, required('APPLE_TEAM_ID'))


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def required(name):
    value = os.environ.get(name)
    if not value:
        raise ValueError('A required signing setting is missing: ' + name)
    return value


def decode(name):
    return base64.b64decode(''.join(required(name).split()), validate=True)


def private_file(path, data):
    path.write_bytes(data)
    path.chmod(0o600)


def env_value(name, value):
    if '\n' in value or '\r' in value:
        raise ValueError('Invalid signing metadata')
    with open(required('GITHUB_ENV'), 'a', encoding='utf-8') as stream:
        stream.write(name + '=' + value + '\n')


def folder():
    return Path(required('RUNNER_TEMP')) / 'orangeone-signing'


def install_api_key():
    root = folder()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = root / 'AuthKey.p8'
    private_file(path, decode('APP_STORE_CONNECT_KEY_BASE64'))
    run('/usr/bin/openssl', 'pkey', '-in', str(path), '-noout')
    env_value('APP_STORE_CONNECT_KEY_FILE', str(path))


def install_signing():
    root = folder()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    certificate = root / 'distribution.p12'
    source_profile = root / 'distribution.mobileprovision'
    private_file(certificate, decode('IOS_CERTIFICATE_BASE64'))
    private_file(source_profile, decode('IOS_PROVISION_PROFILE_BASE64'))
    profile = plistlib.loads(run('/usr/bin/security', 'cms', '-D', '-i', str(source_profile)))
    uuid, name = validate_profile(profile, required('APPLE_TEAM_ID'))
    expected = profile['ApplicationIdentifierPrefix'][0] + '.' + bundle_id()
    validate_entitlements({'keychain-access-groups': [expected]}, profile, required('APPLE_TEAM_ID'))
    # Unsigned archives may omit xcent files; any included requests must be safe.
    archive = Path(required('RUNNER_TEMP')) / 'candidate/Runner.xcarchive'
    for path in archive.rglob('*.xcent'):
        validate_entitlements(plistlib.loads(path.read_bytes()), profile, required('APPLE_TEAM_ID'))
    app = archive / 'Products/Applications/Runner.app'
    if (app / '_CodeSignature').exists():
        entitlements = plistlib.loads(run('/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)))
        validate_entitlements(entitlements, profile, required('APPLE_TEAM_ID'))
    profile_dir = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
    profile_dir.mkdir(parents=True, exist_ok=True)
    destination = profile_dir / (uuid + '.mobileprovision')
    # Hosted runner is ephemeral; record paths before any mutation for always-cleanup.
    keychain = root / 'signing.keychain-db'
    previous = shlex.split(run('/usr/bin/security', 'list-keychains', '-d', 'user').decode())
    private_file(root / 'state.json', json.dumps({'previous': previous, 'profile': str(destination)}).encode())
    private_file(destination, source_profile.read_bytes())
    password = secrets.token_urlsafe(32)
    run('/usr/bin/security', 'create-keychain', '-p', password, str(keychain))
    run('/usr/bin/security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('/usr/bin/security', 'unlock-keychain', '-p', password, str(keychain))
    run('/usr/bin/security', 'import', str(certificate), '-P', required('IOS_CERTIFICATE_PASSWORD'),
        '-T', '/usr/bin/codesign', '-T', '/usr/bin/security', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain))
    run('/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
        '-k', password, str(keychain))
    run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', str(keychain), *previous)
    identities = run('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning', str(keychain))
    if b'Apple Distribution' not in identities:
        raise ValueError('No valid Apple Distribution signing identity was imported.')
    fingerprint = validate_certificate(profile, identities)
    env_value('IOS_CERTIFICATE_SHA1', fingerprint)
    env_value('IOS_PROFILE_UUID', uuid)
    env_value('IOS_PROFILE_NAME', name)


def cleanup():
    root = folder()
    if not root.exists():
        return
    errors = []

    def attempt(operation):
        try:
            operation()
        except (OSError, subprocess.SubprocessError):
            errors.append(True)

    state_file = root / 'state.json'
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text())
            previous = state['previous']
            profile = Path(state['profile'])
            if not isinstance(previous, list) or not all(isinstance(p, str) for p in previous):
                raise ValueError('Invalid cleanup state')
        except (OSError, ValueError, KeyError, TypeError):
            # A damaged record must not skip private files/keychain cleanup.
            errors.append(True)
        else:
            attempt(lambda: run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *previous))
            expected = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
            if profile.parent == expected and re.fullmatch(r'[A-Fa-f0-9-]{36}\.mobileprovision', profile.name):
                attempt(lambda: profile.unlink(missing_ok=True))
    keychain = root / 'signing.keychain-db'
    if keychain.exists():
        attempt(lambda: run('/usr/bin/security', 'delete-keychain', str(keychain)))
    attempt(lambda: shutil.rmtree(root))
    if errors:
        raise ValueError('Some signing cleanup operations failed.')


if __name__ == '__main__':
    try:
        if sys.platform != 'darwin':
            raise ValueError('Signing operations require a hosted macOS runner.')
        operation = sys.argv[1]
        if operation == 'install':
            install_signing()
            install_api_key()
        elif operation == 'api-key':
            install_api_key()
        elif operation == 'cleanup':
            cleanup()
        else:
            raise ValueError('Unsupported signing operation')
    except (ValueError, KeyError, IndexError, OSError, subprocess.SubprocessError, plistlib.InvalidFileException):
        # CalledProcessError may include password arguments. Never echo it.
        sys.exit('Apple signing operation failed. Check required secrets, profile, team and certificate validity.')
