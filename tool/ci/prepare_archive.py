"""Validate a candidate archive as data before it reaches signing tools."""
import os
from pathlib import Path, PurePosixPath
import plistlib
import posixpath
import stat
import subprocess
import zipfile


def validate_zip(path):
    with zipfile.ZipFile(path) as archive:
        for member in archive.infolist():
            name = member.filename
            parts = PurePosixPath(name).parts
            if (not parts or parts[0] != 'Runner.xcarchive' or '..' in parts
                    or name.startswith('/') or '\\' in name):
                raise ValueError('Archive contains an unsafe entry.')
            mode = member.external_attr >> 16
            if stat.S_ISLNK(mode):
                target = archive.read(member).decode('utf-8')
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                if target.startswith('/') or not resolved.startswith('Runner.xcarchive/'):
                    raise ValueError('Archive contains an escaping symlink.')
            elif stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise ValueError('Archive contains an unsupported file type.')


def validate_app(archive, version, build_number):
    root = Path(archive)
    info = plistlib.loads((root / 'Info.plist').read_bytes())
    relative = info.get('ApplicationProperties', {}).get('ApplicationPath')
    if relative != 'Applications/Runner.app':
        raise ValueError('Archive must contain the production Runner app.')
    app = root / 'Products' / relative
    details = plistlib.loads((app / 'Info.plist').read_bytes())
    if (details.get('CFBundleIdentifier') != 'com.orangeone.app'
            or details.get('CFBundleShortVersionString') != version
            or details.get('CFBundleVersion') != build_number):
        raise ValueError('Candidate bundle/version/build does not match the manual request.')
    executable = details.get('CFBundleExecutable')
    if (not isinstance(executable, str) or not executable
            or '/' in executable or '\\' in executable or executable in ('.', '..')):
        raise ValueError('Candidate has no valid application executable.')
    binary = app / executable
    if not binary.is_file() or binary.stat().st_size == 0:
        raise ValueError('Candidate application executable is missing or empty.')


if __name__ == '__main__':
    try:
        temporary = Path(os.environ['RUNNER_TEMP'])
        source = temporary / 'candidate-download/candidate.zip'
        validate_zip(source)
        destination = temporary / 'candidate'
        destination.mkdir(mode=0o700, exist_ok=True)
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(source), str(destination)], check=True)
        validate_app(destination / 'Runner.xcarchive', os.environ['RELEASE_VERSION'], os.environ['RELEASE_BUILD_NUMBER'])
    except (ValueError, OSError, KeyError, subprocess.SubprocessError, zipfile.BadZipFile):
        raise SystemExit('Candidate archive validation failed; no signing credentials were loaded.') from None
