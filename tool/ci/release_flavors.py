"""Production signing identity, independent of native CI flavors/tester groups."""
import json
import os
from pathlib import Path

TARGETS = json.loads(Path(__file__).with_name('testflight_targets.json').read_text())
BUNDLES = {'production': TARGETS['bundle_id']}
GROUPS = TARGETS['groups']


def target_group(value='production'):
    if value not in GROUPS:
        raise ValueError('Unsupported TestFlight target group.')
    return GROUPS[value]


def bundle_id(flavor=None):
    flavor = os.environ.get('RELEASE_FLAVOR', 'production') if flavor is None else flavor
    if flavor not in BUNDLES:
        raise ValueError('Signed releases must use the production flavor.')
    return BUNDLES[flavor]
