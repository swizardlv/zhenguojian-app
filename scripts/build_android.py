import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

from android_build_state import AndroidBuildVersion, ABI_VERSION_CODE_OFFSETS
from app_build import BuildVariant, add_variant_argument
from build_mirrors import china_mirror_environment, mirrored_pub_lockfile


DEFAULT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ABIS = ('arm64-v8a', 'armeabi-v7a', 'x86_64')


def main(argv=None, *, project_root=None, build_meta_dir=None):
    root = Path(project_root or DEFAULT_ROOT).resolve()
    parser = argparse.ArgumentParser(description='Build the 红果鉴 or 真果鉴 Android app.')
    parser.add_argument('--abi', action='append', choices=sorted(ABI_VERSION_CODE_OFFSETS))
    parser.add_argument('--cn-mirrors', action='store_true', help='使用 Flutter 中国镜像和阿里云 Maven 镜像')
    add_variant_argument(parser)
    options = parser.parse_args(argv)
    variant = BuildVariant(options.all_sources)
    environment = os.environ.copy()
    if platform.system() == 'Darwin':
        environment['LANG'] = 'en_US.UTF-8'
        environment['LC_ALL'] = 'en_US.UTF-8'
    environment.setdefault('GOPROXY', 'https://goproxy.cn,direct')
    environment.setdefault('GOSUMDB', 'off')
    flutter = shutil.which('flutter')
    if not flutter:
        raise SystemExit('请先将 Flutter SDK 的 bin 目录加入 PATH。')
    selected_abis = options.abi or DEFAULT_ABIS
    abi_args = [item for abi in options.abi or [] for item in ['--abi', abi]]
    metadata_directory = Path(build_meta_dir) if build_meta_dir else root / '.build-meta'
    with AndroidBuildVersion(metadata_directory, root / 'pubspec.yaml', variant.slug, selected_abis) as build_version:
        with china_mirror_environment(environment, options.cn_mirrors) as env, mirrored_pub_lockfile(root, env):
            if options.cn_mirrors:
                print('本次构建启用国内依赖镜像，保留官方 Maven 仓库备用。', flush=True)
            subprocess.run([sys.executable, str(root / 'scripts' / 'build_native.py'),
                            '--platform', 'android', *abi_args, *variant.arguments],
                           cwd=root, env=env, check=True)
            subprocess.run([flutter, 'pub', 'get', '--enforce-lockfile'],
                           cwd=root, env=env, check=True)
            build_args = [flutter, 'build', 'apk', '--release', '--split-per-abi', '--no-pub',
                          '--build-number', str(build_version.build_number), *variant.flutter_arguments]
            if options.abi:
                targets = {
                    'arm64-v8a': 'android-arm64',
                    'armeabi-v7a': 'android-arm',
                    'x86_64': 'android-x64',
                }
                build_args += ['--target-platform', ','.join(targets[abi] for abi in options.abi)]
            subprocess.run(build_args, cwd=root, env=env, check=True)
            subprocess.run([sys.executable, str(root / 'scripts' / 'package_release.py'),
                            '--platform', 'android', *abi_args, *variant.arguments,
                            '--build-number', str(build_version.build_number)],
                           cwd=root, env=env, check=True)
        build_version.commit()
        print(f'{variant.name} Android build succeeded; build number {build_version.build_number}.',
              flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
