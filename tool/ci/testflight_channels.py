"""DEV and STG TestFlight channels: one app, one bundle ID, three tester groups.

A Flutter flavor only selects configuration (display name, icon, environment,
dart defines). Every signed build, whatever its flavor, uses the production
bundle ID ``ch.orangepos.productscanner`` and the existing production signing
identity; the branch it comes from decides the flavor and the single tester
group it may reach. Production is never reachable from here.
"""
import json
import os
from pathlib import Path
import re

from release_flavors import BUNDLES

ROOT = Path(__file__).resolve().parents[2]
BUNDLE_ID = BUNDLES['production']

# Xcode build setting the non-production configurations use for their bundle
# ID (Runner target only). The TestFlight archive overrides it with BUNDLE_ID.
BUNDLE_SETTING = 'FLAVOR_BUNDLE_ID'

# ref -> channel. The environment is the GitHub Environment holding the
# credentials of that channel; the group key is an allowlisted
# testflight_targets.json entry, never a free-form name.
CHANNELS = {
    'refs/heads/develop': {
        'flavor': 'development', 'group': 'dev',
        'environment': 'ios-development', 'display_name': '[DEV] OrangeONE',
    },
    'refs/heads/staging': {
        'flavor': 'staging', 'group': 'staging',
        'environment': 'ios-staging', 'display_name': '[STG] OrangeONE',
    },
}
EVENTS = ('push', 'workflow_dispatch')
MAX_BUILD = 9999


def channel_for(ref, event):
    if event not in EVENTS:
        raise ValueError('TestFlight delivery runs only for a branch push or a manual dispatch.')
    if ref not in CHANNELS:
        raise ValueError('TestFlight delivery is limited to the develop and staging branches.')
    return CHANNELS[ref]


def is_dry_run(event, requested, enabled):
    """Real uploads need the repository switch; manual runs default to a dry run."""
    return enabled != 'true' or (event == 'workflow_dispatch' and requested != 'false')


def pubspec_version(root=ROOT):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
                      (Path(root) / 'pubspec.yaml').read_text(), re.M)
    if not match:
        raise ValueError('pubspec.yaml needs a version like 1.2.3+45.')
    return match.group(1), int(match.group(2))


def build_floor(root=ROOT):
    """Highest build number that must not be reused (ledger and pubspec)."""
    ledger = json.loads((Path(root) / 'tool/ci/release_versions.json').read_text())
    used = [entry['build'] for entry in ledger['published'] + ledger['reserved']]
    _, pubspec_build = pubspec_version(root)
    return max(used + [pubspec_build - 1])


def validate_flavor_configuration(flavor, root=ROOT):
    """The nonsecret dart-define file must select the same environment as the flavor."""
    values = json.loads((Path(root) / f'config/{flavor}.example.json').read_text())
    if values.get('APP_ENVIRONMENT') != flavor:
        raise ValueError(f'config/{flavor}.example.json does not select the {flavor} environment.')
    if values.get('ODOO_BASE_URL'):
        raise ValueError('Builds must not bake in a backend URL; the POS QR selects it.')
    return values


def plan(environ=None, root=ROOT):
    environ = os.environ if environ is None else environ
    event = environ.get('GITHUB_EVENT_NAME', '')
    channel = channel_for(environ.get('GITHUB_REF', ''), event)
    validate_flavor_configuration(channel['flavor'], root)
    version, _ = pubspec_version(root)
    return {
        'flavor': channel['flavor'],
        'group': channel['group'],
        'environment': channel['environment'],
        'display_name': channel['display_name'],
        'version': version,
        'build_floor': str(build_floor(root)),
        'dry_run': 'true' if is_dry_run(
            event, environ.get('REQUESTED_DRY_RUN', ''),
            environ.get('TESTFLIGHT_CD_ENABLED', '')) else 'false',
    }


def valid_build_number(value):
    return bool(re.fullmatch(r'[1-9]\d{0,3}', str(value)))


if __name__ == '__main__':
    try:
        outputs = plan()
    except (ValueError, OSError, KeyError) as error:
        raise SystemExit(str(error)) from None
    destination = os.environ.get('GITHUB_OUTPUT')
    lines = ''.join(f'{key}={value}\n' for key, value in outputs.items())
    if destination:
        with open(destination, 'a', encoding='utf-8') as handle:
            handle.write(lines)
    print(lines, end='')
