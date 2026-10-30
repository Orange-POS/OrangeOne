"""Unsigned archive of the DEV or STG flavor under the production bundle ID.

Runs in the secret-free build job. ``flutter build ipa`` cannot override build
settings, so the archive is produced with Flutter's documented two-step flow:
``flutter build ios --config-only`` writes the flavor's configuration, then
``xcodebuild archive`` overrides only ``FLAVOR_BUNDLE_ID``. That setting is read
by the Runner target alone, so plugin frameworks keep their own identifiers.

``--no-codesign`` is required on the configuration step: for a release device
build Flutter otherwise looks for a development signing certificate (reading the
flavor's own ``.dev``/``.stg`` bundle ID) before it writes the configuration, and
this secret-free job has none. Signing happens only in the protected deliver job.

The flavor's Firebase configuration (project identifiers, not credentials) is
written before the build and verified in the finished archive, so a distributable
build can never silently lack Crashlytics or point at another environment's
project. ``--split-debug-info`` keeps the Dart symbols for the Crashlytics upload.
"""
import os
from pathlib import Path
import plistlib
import subprocess

import firebase_config
import prepare_archive
from testflight_channels import BUNDLE_ID, BUNDLE_SETTING, CHANNELS, valid_build_number, validate_flavor_configuration

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / 'build/ios/archive/Runner.xcarchive'
# Absolute: Xcode's Flutter script phase runs from ios/, not the repository root.
SYMBOLS = str(ROOT / 'build/symbols/ios')
FLAVORS = {channel['flavor']: channel for channel in CHANNELS.values()}


def commands(flavor, version, build_number):
    if flavor not in FLAVORS:
        raise ValueError('Only the development and staging flavors use this archive path.')
    if not valid_build_number(build_number):
        raise ValueError('Use an allocated build integer from 1 to 9999.')
    return [
        ['flutter', 'build', 'ios', '--config-only', '--release',
         '--no-codesign', f'--split-debug-info={SYMBOLS}', '--flavor', flavor, '--target', f'lib/main_{flavor}.dart',
         f'--dart-define-from-file=config/{flavor}.example.json',
         f'--build-name={version}', f'--build-number={build_number}'],
        ['xcodebuild', 'archive',
         '-workspace', 'ios/Runner.xcworkspace', '-scheme', flavor,
         '-configuration', f'Release-{flavor}',
         '-destination', 'generic/platform=iOS',
         '-archivePath', str(ARCHIVE),
         'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=',
         f'{BUNDLE_SETTING}={BUNDLE_ID}'],
    ]


def verify(flavor, version, build_number, archive=ARCHIVE):
    """Identity, flavor display name and bundle ID of the archive just built."""
    prepare_archive.validate_app(archive, version, build_number)
    details = plistlib.loads((Path(archive) / 'Products/Applications/Runner.app/Info.plist').read_bytes())
    if details.get('CFBundleDisplayName') != FLAVORS[flavor]['display_name']:
        raise ValueError('Archive does not carry the selected flavor configuration.')


def main(environ=None, run=subprocess.run, write_config=firebase_config.write,
         verify_config=firebase_config.verify_ios):
    environ = os.environ if environ is None else environ
    flavor, version, number = (environ[key] for key in ('FLAVOR', 'RELEASE_VERSION', 'RELEASE_BUILD_NUMBER'))
    validate_flavor_configuration(flavor, ROOT)
    write_config('ios', flavor, environ)
    for command in commands(flavor, version, number):
        run(command, cwd=ROOT, check=True, env=dict(environ))
    verify(flavor, version, number)
    verify_config(ARCHIVE, flavor, environ)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:  # ConfigError is a ValueError
        raise SystemExit(f'Flavor archive failed: {error}') from None
