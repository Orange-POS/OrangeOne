"""Keep the app version above everything already used in App Store Connect."""
import json
from pathlib import Path
import re
import unittest

from validate_release import validate

ROOT = Path(__file__).resolve().parents[2]
LEDGER = json.loads((Path(__file__).with_name('release_versions.json')).read_text())
VERSION = re.compile(r'\d+\.\d+\.\d+')


def pubspec_version():
    match = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
                      (ROOT / 'pubspec.yaml').read_text(), re.M)
    assert match, 'pubspec.yaml needs a version like 1.2.3+45'
    *marketing, build = (int(part) for part in match.groups())
    return tuple(marketing), build


def entries():
    return LEDGER['published'] + LEDGER['reserved']


class VersioningTest(unittest.TestCase):
    def test_ledger_is_well_formed_and_has_no_duplicates(self):
        seen = set()
        for entry in entries():
            with self.subTest(entry=entry):
                self.assertRegex(entry['version'], VERSION)
                self.assertIsInstance(entry['build'], int)
                self.assertGreaterEqual(entry['build'], 1)
                self.assertLessEqual(entry['build'], 9999)
                self.assertTrue(entry['evidence'])
                key = (entry['version'], entry['build'])
                self.assertNotIn(key, seen)
                seen.add(key)

    def test_pubspec_build_number_is_above_every_used_build(self):
        _, build = pubspec_version()
        used = max(entry['build'] for entry in entries())
        self.assertGreater(
            build, used,
            f'pubspec build number {build} must exceed the highest used build {used}')
        self.assertLessEqual(build, 9999)

    def test_pubspec_marketing_version_is_not_below_a_published_one(self):
        marketing, _ = pubspec_version()
        # Unconfirmed (reserved) dispatches do not close a version train.
        highest = max(tuple(int(p) for p in e['version'].split('.')) for e in LEDGER['published'])
        self.assertGreaterEqual(
            marketing, highest,
            'Apple closes lower version trains; keep pubspec at or above the highest uploaded version')

    def test_pubspec_version_is_accepted_by_the_release_validator(self):
        marketing, build = pubspec_version()
        validate({
            'RELEASE_FLAVOR': 'production',
            'TARGET_GROUP': 'dev',
            'GITHUB_REF': 'refs/heads/main',
            'GITHUB_EVENT_NAME': 'workflow_dispatch',
            'RELEASE_VERSION': '.'.join(str(part) for part in marketing),
            'RELEASE_BUILD_NUMBER': str(build),
            'OPERATION': 'testflight',
        })

    def test_the_pubspec_pair_is_not_already_in_the_ledger(self):
        marketing, build = pubspec_version()
        pair = ('.'.join(str(part) for part in marketing), build)
        self.assertNotIn(pair, {(e['version'], e['build']) for e in entries()})


if __name__ == '__main__':
    unittest.main()
