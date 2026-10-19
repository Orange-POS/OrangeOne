"""Export only: never build, run app binaries or execute archive build scripts."""
import os
from pathlib import Path
import plistlib
import subprocess

def export():
    destination = Path.cwd() / 'build/ios/ipa'
    destination.mkdir(parents=True, exist_ok=True)
    options = Path(os.environ['RUNNER_TEMP']) / 'store-export.plist'
    options.write_bytes(plistlib.dumps({
        'method': 'app-store-connect',
        'signingStyle': 'manual',
        'signingCertificate': 'Apple Distribution',
        'teamID': os.environ['APPLE_TEAM_ID'],
        'provisioningProfiles': {'com.orangeone.app': os.environ['IOS_PROFILE_NAME']},
    }))
    subprocess.run([
        '/usr/bin/xcodebuild', '-exportArchive',
        '-archivePath', str(Path(os.environ['RUNNER_TEMP']) / 'candidate/Runner.xcarchive'),
        '-exportPath', str(destination), '-exportOptionsPlist', str(options),
    ], check=True)
    ipas = list(destination.glob('*.ipa'))
    if len(ipas) != 1 or ipas[0].stat().st_size == 0:
        raise SystemExit('Expected exactly one nonempty exported production IPA.')


if __name__ == '__main__':
    export()
