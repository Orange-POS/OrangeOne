"""Verify the Android release keystore and the signed production APK.

The existing release keystore is the app's identity: users can install updates
only when the new APK is signed by the same certificate and has a higher version
code. Nothing here bypasses Android's checks; it only refuses to hand out an
APK that Android itself would reject or that carries another identity.

Passwords are read from the environment and passed to ``keytool`` through
``-storepass:env``, so they never appear in a process list or in logs.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PACKAGE = 'com.orangeone.app'
FINGERPRINT = re.compile(r'[0-9A-F]{2}(?::[0-9A-F]{2}){31}')


def normalize_fingerprint(value):
    """Accept aa:bb.. or AABB.. (64 hex digits) and return upper-case colon form."""
    digits = re.sub(r'[^0-9A-Fa-f]', '', value or '').upper()
    if len(digits) != 64:
        raise ValueError('A SHA-256 certificate fingerprint has 64 hex digits.')
    return ':'.join(digits[i:i + 2] for i in range(0, 64, 2))


def keytool_fingerprint(output):
    match = re.search(r'SHA-?256:\s*(' + FINGERPRINT.pattern + ')', output)
    if not match:
        raise ValueError('The keystore listing has no SHA-256 fingerprint.')
    return match.group(1)


def verify_keystore(path, alias, expected, environ=None, run=subprocess.run):
    """The keystore opens with the supplied passwords and holds the pinned identity."""
    environ = os.environ if environ is None else environ
    expected = normalize_fingerprint(expected)
    result = run(['keytool', '-list', '-v', '-keystore', str(path), '-alias', alias,
                  '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD'],
                 capture_output=True, text=True, env=environ)
    if result.returncode != 0:
        raise ValueError('The Android keystore could not be opened with the supplied alias and password.')
    if keytool_fingerprint(result.stdout) != expected:
        raise ValueError('The keystore certificate is not the pinned release identity; refusing to sign.')
    return expected


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for block in iter(lambda: handle.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def parse_signature(output):
    """-> (fingerprint, schemes) from ``apksigner verify --verbose --print-certs``."""
    certificate = re.search(r'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', output)
    if not certificate:
        raise ValueError('The APK has no signing certificate.')
    schemes = {int(number) for number in re.findall(r'Verified using v(\d) scheme[^:]*:\s*true', output)}
    signers = re.search(r'Number of signers:\s*(\d+)', output)
    if not signers or int(signers.group(1)) != 1:
        raise ValueError('The APK must have exactly one signer.')
    return normalize_fingerprint(certificate.group(1)), schemes


def parse_badging(output):
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'", output)
    if not package:
        raise ValueError('Could not read the APK package information.')
    return {
        'package': package.group(1),
        'version_code': int(package.group(2)),
        'version_name': package.group(3),
        'debuggable': 'application-debuggable' in output,
    }


def inspect(apk, apksigner='apksigner', aapt='aapt', run=subprocess.run):
    signature = run([apksigner, 'verify', '--verbose', '--print-certs', str(apk)],
                    capture_output=True, text=True)
    if signature.returncode != 0:
        raise ValueError('apksigner rejected the APK signature.')
    fingerprint, schemes = parse_signature(signature.stdout)
    badging = run([aapt, 'dump', 'badging', str(apk)], capture_output=True, text=True)
    if badging.returncode != 0:
        raise ValueError('aapt could not read the APK.')
    return {'fingerprint': fingerprint, 'schemes': schemes, **parse_badging(badging.stdout)}


def verify_apk(apk, version, version_code, expected, **tools):
    """Signed with the pinned identity, correct package/version, not debuggable."""
    details = inspect(apk, **tools)
    if details['fingerprint'] != normalize_fingerprint(expected):
        raise ValueError('The APK is not signed with the pinned release identity.')
    if not details['schemes'] & {2, 3}:
        raise ValueError('The APK needs a v2 or v3 signature for current Android versions.')
    if details['package'] != PACKAGE:
        raise ValueError('Unexpected application ID.')
    if details['version_name'] != version or details['version_code'] != int(version_code):
        raise ValueError('The APK version does not match the release.')
    if details['debuggable']:
        raise ValueError('A release APK must not be debuggable.')
    return details


def check_upgrade(old, new):
    """An update installs only with the same signer and a higher version code."""
    if old['fingerprint'] != new['fingerprint']:
        raise ValueError('Signer changed: Android would refuse this update.')
    if new['package'] != old['package']:
        raise ValueError('Application ID changed: this would be a different app.')
    if new['version_code'] <= old['version_code']:
        raise ValueError('The version code must increase for Android to accept the update.')
    return True


def write_manifest(apk, details, destination):
    manifest = {
        'file': Path(apk).name,
        'sha256': sha256_file(apk),
        'size': Path(apk).stat().st_size,
        'package': details['package'],
        'version_name': details['version_name'],
        'version_code': details['version_code'],
        'signing_certificate_sha256': details['fingerprint'],
    }
    Path(destination).write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return manifest


def main(argv, environ=None):
    environ = os.environ if environ is None else environ
    command = argv[1] if len(argv) > 1 else ''
    if command == 'keystore':
        verify_keystore(environ['ANDROID_KEYSTORE_PATH'], environ['ANDROID_KEYSTORE_ALIAS'],
                        environ['ANDROID_SIGNING_CERT_SHA256'], environ)
        print('The release keystore opens and matches the pinned identity.')
    elif command == 'verify':
        apk = argv[2]
        details = verify_apk(apk, environ['RELEASE_VERSION'], environ['ANDROID_VERSION_CODE'],
                             environ['ANDROID_SIGNING_CERT_SHA256'])
        manifest = write_manifest(apk, details, argv[3])
        print(f"Verified {manifest['file']} {manifest['version_name']} ({manifest['version_code']}) "
              f"sha256 {manifest['sha256']}")
    elif command == 'upgrade':
        check_upgrade(inspect(argv[2]), inspect(argv[3]))
        print('The new APK is a valid update of the old one.')
    else:
        raise ValueError('Use: keystore | verify <apk> <manifest> | upgrade <old> <new>')


if __name__ == '__main__':
    try:
        main(sys.argv)
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(str(error) or 'Android APK check failed.') from None
