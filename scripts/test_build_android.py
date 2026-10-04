import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest import mock

from android_build_state import AndroidBuildVersion, STATE_FILENAME, recorded_build
from app_build import BuildVariant
from build_android import main as build_android


SCRIPTS = Path(__file__).resolve().parent
PROJECT = SCRIPTS.parent


class AndroidBuildVariantTests(unittest.TestCase):
    def test_ids_labels_and_output_names_are_distinct_and_stable(self):
        red = BuildVariant()
        full = BuildVariant(True)
        self.assertEqual(red.name, '红果鉴')
        self.assertEqual(full.name, '真果鉴')
        self.assertEqual(red.android_application_id, 'com.duanju.duanju_app')
        self.assertEqual(full.android_application_id, 'com.duanju.duanju_app.zhenguojian')
        red_apk = red.android_artifact_filename('0.2.56', 63, 'armeabi-v7a')
        full_apk = full.android_artifact_filename('0.2.56', 64, 'armeabi-v7a')
        self.assertEqual(red_apk, 'hongguojian-0.2.56+63-armeabi-v7a.apk')
        self.assertEqual(full_apk, 'zhenguojian-0.2.56+64-armeabi-v7a.apk')
        self.assertNotEqual(red_apk, full_apk)

    def test_gradle_uses_variant_id_and_display_label_without_fixed_authority(self):
        gradle = (PROJECT / 'android/app/build.gradle.kts').read_text(encoding='utf-8')
        manifest = (PROJECT / 'android/app/src/main/AndroidManifest.xml').read_text(encoding='utf-8')
        packager = (SCRIPTS / 'package_release.py').read_text(encoding='utf-8')
        self.assertIn(
            'val appApplicationId = if (allSources) "com.duanju.duanju_app.zhenguojian" '
            'else "com.duanju.duanju_app"',
            gradle,
        )
        self.assertIn('applicationId = appApplicationId', gradle)
        self.assertIn('manifestPlaceholders["appLabel"] = if (allSources) "真果鉴" else "红果鉴"', gradle)
        self.assertNotIn('android:authorities=', manifest)
        self.assertIn('variant.android_artifact_filename(version_name, build_number, abi)', packager)

    def test_armv7_entry_points_select_the_intended_edition(self):
        red = (SCRIPTS / 'build_android_armv7_hongguojian.sh').read_text(encoding='utf-8')
        full = (SCRIPTS / 'build_android_armv7_zhenguojian.sh').read_text(encoding='utf-8')
        shared = (SCRIPTS / 'build_android_armv7.sh').read_text(encoding='utf-8')
        self.assertIn('build_android_armv7.sh" hongguojian', red)
        self.assertIn('build_android_armv7.sh" zhenguojian', full)
        self.assertIn('variant_args=(--all-sources)', shared)
        self.assertIn('exec python3 "$BUILDER" --abi armeabi-v7a', shared)


class AndroidBuildStateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='android-build-state-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.metadata = self.root / '.build-meta'
        self.pubspec = self.root / 'pubspec.yaml'
        self.pubspec.write_text('name: test\nversion: 0.2.56+62\n', encoding='utf-8')

    def manager(self, variant='hongguojian', abis=('armeabi-v7a',)):
        return AndroidBuildVersion(self.metadata, self.pubspec, variant, abis)

    def test_failed_or_abandoned_build_does_not_consume_code(self):
        with self.manager() as abandoned:
            self.assertEqual(abandoned.build_number, 63)
        self.assertFalse((self.metadata / STATE_FILENAME).exists())
        with self.manager() as successful:
            self.assertEqual(successful.build_number, 63)
            successful.commit()
        with self.manager() as next_build:
            self.assertEqual(next_build.build_number, 64)

    def test_all_abis_advance_past_the_highest_previous_android_version_code(self):
        with self.manager('zhenguojian', ('arm64-v8a',)) as first:
            self.assertEqual(first.build_number, 63)
            self.assertEqual(first.version_code('arm64-v8a'), 2063)
            first.commit()
        with self.manager('hongguojian', ('armeabi-v7a',)) as next_build:
            self.assertEqual(next_build.build_number, 1064)
            self.assertEqual(next_build.version_code('armeabi-v7a'), 2064)
            next_build.commit()
        self.assertEqual(recorded_build(self.metadata, 'zhenguojian', 'arm64-v8a'), (63, 2063))
        self.assertEqual(recorded_build(self.metadata, 'hongguojian', 'armeabi-v7a'), (1064, 2064))

    def test_state_write_is_atomic_and_valid_json(self):
        with self.manager() as build:
            build.commit()
        state_path = self.metadata / STATE_FILENAME
        state = json.loads(state_path.read_text(encoding='utf-8'))
        self.assertEqual(state['last_build_number'], 63)
        self.assertEqual(state['outputs']['hongguojian']['armeabi-v7a'], 1063)
        self.assertEqual(list(self.metadata.glob('*.tmp')), [])

    def test_concurrent_builds_receive_distinct_increasing_numbers(self):
        worker = textwrap.dedent('''
            import sys
            import time
            from pathlib import Path
            from android_build_state import AndroidBuildVersion
            with AndroidBuildVersion(Path(sys.argv[1]), Path(sys.argv[2]), 'hongguojian', ['armeabi-v7a']) as build:
                print(build.build_number, flush=True)
                time.sleep(0.08)
                build.commit()
        ''')
        workers = [
            subprocess.Popen(
                [sys.executable, '-c', worker, str(self.metadata), str(self.pubspec)],
                env={
                    **os.environ,
                    'PYTHONPATH': str(SCRIPTS) + os.pathsep + os.environ.get('PYTHONPATH', ''),
                },
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for _ in range(4)
        ]
        results = []
        for process in workers:
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stderr)
            results.append(int(stdout.strip()))
        self.assertEqual(sorted(results), [63, 64, 65, 66])
        state = json.loads((self.metadata / STATE_FILENAME).read_text(encoding='utf-8'))
        self.assertEqual(state['last_build_number'], 66)
        self.assertEqual(state['outputs']['hongguojian']['armeabi-v7a'], 1066)


class AndroidBuildInvocationTests(unittest.TestCase):
    @staticmethod
    def calls(run):
        return [call.args[0] for call in run.call_args_list]

    def test_both_editions_propagate_flags_and_increment_version_numbers(self):
        with tempfile.TemporaryDirectory(prefix='android-build-invocation-') as temporary:
            metadata = Path(temporary) / '.build-meta'
            with mock.patch.dict(os.environ, {'PATH': '/mock-tools'}, clear=True), \
                    mock.patch('build_android.shutil.which', return_value='/mock-tools/flutter'), \
                    mock.patch('build_android.subprocess.run') as run:
                build_android(['--abi', 'armeabi-v7a'], project_root=PROJECT, build_meta_dir=metadata)
                red_calls = self.calls(run)
                build_android(['--all-sources', '--abi', 'armeabi-v7a'], project_root=PROJECT,
                              build_meta_dir=metadata)
                full_calls = self.calls(run)[len(red_calls):]

        self.assertEqual(len(red_calls), 4)
        self.assertEqual(len(full_calls), 4)
        for calls, all_sources, expected_build_number in (
            (red_calls, False, '63'),
            (full_calls, True, '64'),
        ):
            native = next(args for args in calls if any(str(arg).endswith('build_native.py') for arg in args))
            flutter = next(args for args in calls if len(args) > 2 and args[1:3] == ['build', 'apk'])
            package = next(args for args in calls if any(str(arg).endswith('package_release.py') for arg in args))
            expected_define = '--dart-define=ALL_SOURCES=' + str(all_sources).lower()
            self.assertEqual('--all-sources' in native, all_sources)
            self.assertEqual('--all-sources' in package, all_sources)
            self.assertIn(expected_define, flutter)
            self.assertEqual(flutter[flutter.index('--build-number') + 1], expected_build_number)
            self.assertEqual(package[package.index('--build-number') + 1], expected_build_number)
            self.assertEqual(native[native.index('--abi') + 1], 'armeabi-v7a')
            self.assertEqual(package[package.index('--abi') + 1], 'armeabi-v7a')

    def test_build_failure_leaves_next_success_on_the_same_number(self):
        with tempfile.TemporaryDirectory(prefix='android-build-failure-') as temporary:
            metadata = Path(temporary) / '.build-meta'

            def fail_native(arguments, **kwargs):
                if any(str(argument).endswith('build_native.py') for argument in arguments):
                    raise subprocess.CalledProcessError(1, arguments)
                return subprocess.CompletedProcess(arguments, 0)

            with mock.patch.dict(os.environ, {'PATH': '/mock-tools'}, clear=True), \
                    mock.patch('build_android.shutil.which', return_value='/mock-tools/flutter'), \
                    mock.patch('build_android.subprocess.run', side_effect=fail_native):
                with self.assertRaises(subprocess.CalledProcessError):
                    build_android(['--abi', 'armeabi-v7a'], project_root=PROJECT,
                                  build_meta_dir=metadata)
            self.assertFalse((metadata / STATE_FILENAME).exists())

            with mock.patch.dict(os.environ, {'PATH': '/mock-tools'}, clear=True), \
                    mock.patch('build_android.shutil.which', return_value='/mock-tools/flutter'), \
                    mock.patch('build_android.subprocess.run') as run:
                build_android(['--abi', 'armeabi-v7a'], project_root=PROJECT,
                              build_meta_dir=metadata)
            flutter = next(args for args in self.calls(run)
                           if len(args) > 2 and args[1:3] == ['build', 'apk'])
            self.assertEqual(flutter[flutter.index('--build-number') + 1], '63')


if __name__ == '__main__':
    unittest.main()
