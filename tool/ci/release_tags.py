"""Production releases: only an approved, published GitHub Release of a version tag.

A normal commit, merge or branch push never reaches the production workflows.
A release is accepted when it is published (not a draft, not a pre-release), its
tag is exactly ``vX.Y.Z``, the tag points at a commit that is on ``main``, the
tag version equals the ``pubspec.yaml`` version of that commit, and the
version is not below one already uploaded to App Store Connect. The Android
version code (the pubspec build number) must also be above that of every
earlier release tag, so app updates are always accepted by Android.
"""
import json
import os
from pathlib import Path
import re
import subprocess

from testflight_channels import build_floor, pubspec_version, validate_flavor_configuration

ROOT = Path(__file__).resolve().parents[2]
TAG = re.compile(r'v(\d+)\.(\d+)\.(\d+)')
SHA = re.compile(r'[a-f0-9]{40}')
FLAVOR = 'production'
GROUP = 'production'
ENVIRONMENT = 'ios-production'
ANDROID_ENVIRONMENT = 'android-release'


def parse_tag(tag):
    match = TAG.fullmatch(tag or '')
    if not match:
        raise ValueError('Production releases need a version tag like v1.2.3.')
    return '.'.join(match.groups())


def validate_release(event, ref, sha, root=ROOT):
    """-> marketing version of an approved release; raises ValueError otherwise."""
    release = (event or {}).get('release') or {}
    if (event or {}).get('action') != 'published':
        raise ValueError('Only a published GitHub Release can start a production build.')
    if release.get('draft') or release.get('prerelease'):
        raise ValueError('Drafts and pre-releases are not production releases.')
    tag = release.get('tag_name', '')
    version = parse_tag(tag)
    if ref != f'refs/tags/{tag}':
        raise ValueError('The workflow ref must be the release tag.')
    if not SHA.fullmatch(sha or ''):
        raise ValueError('Invalid release commit.')
    pubspec, _ = pubspec_version(root)
    if pubspec != version:
        raise ValueError(f'Tag {tag} does not match the pubspec.yaml version {pubspec}.')
    return version


def ledger_marketing_floor(root=ROOT):
    ledger = json.loads((Path(root) / 'tool/ci/release_versions.json').read_text())
    return max(tuple(int(part) for part in entry['version'].split('.'))
               for entry in ledger['published'])


def require_version_not_below_published(version, root=ROOT):
    if tuple(int(part) for part in version.split('.')) < ledger_marketing_floor(root):
        raise ValueError('Apple closes lower version trains; the release version is below one already uploaded.')


def require_on_main(sha, run=subprocess.run):
    """The tagged commit must be reachable from origin/main (reviewed code only)."""
    result = run(['git', 'merge-base', '--is-ancestor', sha, 'origin/main'], cwd=ROOT)
    if result.returncode != 0:
        raise ValueError('The release tag must point at a commit that is on main.')


def earlier_builds(current_tag, git):
    """Pubspec build numbers of every other release tag (git is injected)."""
    builds = []
    for tag in git(['tag', '--list', 'v*']).split():
        if tag == current_tag or not TAG.fullmatch(tag):
            continue
        match = re.search(r'^version:\s*\d+\.\d+\.\d+\+(\d+)\s*$',
                          git(['show', f'{tag}:pubspec.yaml']), re.M)
        if match:
            builds.append(int(match.group(1)))
    return builds


def require_new_version_code(current_tag, build, git):
    earlier = earlier_builds(current_tag, git)
    if earlier and build <= max(earlier):
        raise ValueError(f'Build number {build} must be above {max(earlier)} of earlier releases '
                         '(it is the Android version code).')


def git_output(arguments):
    return subprocess.run(['git', *arguments], cwd=ROOT, check=True, capture_output=True,
                          text=True).stdout


def is_dry_run(enabled):
    """Real production uploads need their own repository switch."""
    return enabled != 'true'


def plan(environ=None, root=ROOT, git=git_output, run=subprocess.run):
    environ = os.environ if environ is None else environ
    if environ.get('GITHUB_EVENT_NAME') != 'release':
        raise ValueError('Production builds start only from a GitHub Release.')
    event = json.loads(Path(environ['GITHUB_EVENT_PATH']).read_text(encoding='utf-8'))
    sha = environ.get('GITHUB_SHA', '')
    version = validate_release(event, environ.get('GITHUB_REF', ''), sha, root)
    require_version_not_below_published(version, root)
    require_on_main(sha, run)
    _, build = pubspec_version(root)
    require_new_version_code(event['release']['tag_name'], build, git)
    validate_flavor_configuration(FLAVOR, root)
    return {
        'tag': event['release']['tag_name'],
        'version': version,
        'environment': ENVIRONMENT,
        'group': GROUP,
        'flavor': FLAVOR,
        'build_floor': str(build_floor(root)),
        'android_version_code': str(build),
        'dry_run': 'true' if is_dry_run(environ.get('PRODUCTION_RELEASE_ENABLED', '')) else 'false',
    }


if __name__ == '__main__':
    try:
        outputs = plan()
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from None
    lines = ''.join(f'{key}={value}\n' for key, value in outputs.items())
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as handle:
            handle.write(lines)
    print(lines, end='')
