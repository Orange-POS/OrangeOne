"""Check repository flavor wiring without Gradle, Xcode or distribution secrets."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
FLAVORS = ('development', 'staging', 'production')


class NativeFlavorTest(unittest.TestCase):
    def test_all_entrypoints_configs_and_gradle_flavors_exist(self):
        gradle = (ROOT / 'android/app/build.gradle.kts').read_text()
        for flavor in FLAVORS:
            with self.subTest(flavor=flavor):
                self.assertTrue((ROOT / f'lib/main_{flavor}.dart').is_file())
                self.assertTrue((ROOT / f'config/{flavor}.example.json').is_file())
                self.assertIn(f'create("{flavor}")', gradle)

    def test_shared_xcode_schemes_archive_matching_release_configuration(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        for flavor in FLAVORS:
            with self.subTest(flavor=flavor):
                scheme = ET.parse(ROOT / f'ios/Runner.xcodeproj/xcshareddata/xcschemes/{flavor}.xcscheme')
                self.assertEqual(scheme.find('ArchiveAction').get('buildConfiguration'), f'Release-{flavor}')
                self.assertIn(f'Release-{flavor}', project)

    def test_xcode_bundle_ids_match_signing_identity_and_flavor(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        blocks = re.findall(r'/\* ([^*]+) \*/ = \{\s*isa = XCBuildConfiguration;(.*?)\n\t\t\};', project, re.S)
        checked = 0
        for configuration, body in blocks:
            match = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', body)
            if not match:
                continue
            bundle = match.group(1)
            if bundle == '"$(FLAVOR_BUNDLE_ID)"':
                # Flavor configurations name their identifier in one overridable
                # setting (the TestFlight archive overrides it); the default is
                # still the flavor's own bundle ID.
                bundle = re.search(r'FLAVOR_BUNDLE_ID = ([^;]+);', body).group(1)
            suffix = '.RunnerTests' if bundle.endswith('.RunnerTests') else (
                '.dev' if configuration.endswith('development') else
                '.stg' if configuration.endswith('staging') else '')
            with self.subTest(configuration=configuration, bundle=bundle):
                self.assertEqual(bundle, 'ch.orangepos.productscanner' + suffix)
            checked += 1
        self.assertGreater(checked, 0)

    def test_native_workflows_keep_flavor_matrices_and_merge_queue_coverage(self):
        for name in ('android.yaml', 'ios.yaml'):
            with self.subTest(workflow=name):
                workflow = (ROOT / '.github/workflows' / name).read_text()
                self.assertIn('flavor: [development, staging, production]', workflow)
                self.assertIn('  push:', workflow)
                self.assertIn('  pull_request:', workflow)
                self.assertIn('  merge_group:', workflow)
                self.assertIn('lib/main_${{ matrix.flavor }}.dart', workflow)


if __name__ == '__main__':
    unittest.main()
