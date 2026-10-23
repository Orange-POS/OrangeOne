"""Export only: never build, run app binaries or execute archive build scripts."""
import os
from pathlib import Path
import plistlib
import subprocess
from prepare_archive import validate_app
from release_flavors import bundle_id
from ios_signing import verify_export

# Resolve from the trusted script, never Fastlane's process working directory.
EXPORT_DIRECTORY = Path(__file__).resolve().parents[2] / 'build/ios/ipa'

def export():
    archive = Path(os.environ['RUNNER_TEMP']) / 'candidate/Runner.xcarchive'
    validate_app(archive, os.environ['RELEASE_VERSION'], os.environ['RELEASE_BUILD_NUMBER'])
    destination = EXPORT_DIRECTORY
    destination.mkdir(parents=True, exist_ok=True)
    previous = list(destination.glob('*.ipa'))
    if previous:
        raise ValueError(f'Export destination contains {len(previous)} previous IPA candidate(s): {destination}')
    options = Path(os.environ['RUNNER_TEMP']) / 'store-export.plist'
    options.write_bytes(plistlib.dumps({
        'method': 'app-store-connect',
        'signingStyle': 'manual',
        'signingCertificate': os.environ.get('IOS_CERTIFICATE_SHA1', 'Apple Distribution'),
        'teamID': os.environ['APPLE_TEAM_ID'],
        'provisioningProfiles': {bundle_id(): os.environ['IOS_PROFILE_NAME']},
    }))
    subprocess.run([
        '/usr/bin/xcodebuild', '-exportArchive',
        '-archivePath', str(archive),
        '-exportPath', str(destination), '-exportOptionsPlist', str(options),
    ], check=True)
    ipas = list(destination.glob('*.ipa'))
    if len(ipas) != 1 or ipas[0].stat().st_size == 0:
        raise SystemExit(f'Expected one nonempty exported IPA; found {len(ipas)} candidate(s) in {destination}')
    verify_export(ipas[0])


if __name__ == '__main__':
    export()
