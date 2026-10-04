import argparse
import hashlib
import os
import re
import subprocess
import zipfile
from pathlib import Path

from android_build_state import recorded_build
from app_build import BuildVariant, add_variant_argument


ROOT = Path(__file__).resolve().parents[1]
CERTIFICATE = 'd0af8f305e4ae161308fbd050d907c57613662500f574f50da1e7b0d72f44885'


def android_tool(name):
    home = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT', ''))
    matches = sorted(home.glob('build-tools/*/' + name))
    if not matches:
        raise SystemExit('找不到 Android 构建工具：' + name)
    return str(matches[-1])


def main():
    parser = argparse.ArgumentParser()
    add_variant_argument(parser)
    variant = BuildVariant(parser.parse_args().all_sources)
    version = re.search(r'(?m)^version:\s*(\S+)', (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'))
    if not version:
        raise SystemExit('pubspec.yaml 缺少合法版本号。')
    version_name = version.group(1).split('+', 1)[0]
    recorded = recorded_build(ROOT / '.build-meta', variant.slug, 'arm64-v8a')
    if recorded is None:
        raise SystemExit('找不到该版本的成功构建记录；请先通过 scripts/build_android.py 构建此版本。')
    build_number, version_code = recorded
    apk_name = variant.android_artifact_filename(version_name, build_number, 'arm64-v8a')
    apk = ROOT / 'dist' / 'android' / apk_name
    if not apk.is_file():
        raise SystemExit('缺少 APK：' + str(apk))
    checksums = (apk.parent / 'SHA256SUMS.txt').read_text(encoding='ascii').splitlines()
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    if f'{digest}  {apk.name}' not in checksums:
        raise SystemExit('APK SHA-256 不匹配')
    signed = subprocess.run([android_tool('apksigner'), 'verify', '--verbose', '--print-certs', str(apk)],
                            check=True, capture_output=True, text=True).stdout
    if 'Verified using v2 scheme (APK Signature Scheme v2): true' not in signed:
        raise SystemExit('APK 缺少 v2 签名')
    signers = re.findall(r'certificate SHA-256 digest:\s*([0-9a-fA-F]+)', signed)
    if not signers or any(signer.lower() != CERTIFICATE for signer in signers):
        raise SystemExit('APK 签名证书不匹配')
    badging = subprocess.run([android_tool('aapt'), 'dump', 'badging', str(apk)],
                             check=True, capture_output=True, text=True).stdout
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'",
                        badging, re.MULTILINE)
    expected = (variant.android_application_id, str(version_code), version_name)
    if not package or package.groups() != expected:
        raise SystemExit('APK 应用 ID 或版本不匹配')
    if f"application-label:'{variant.name}'" not in badging:
        raise SystemExit('APK 应用名称不匹配')
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
    required = {f'lib/arm64-v8a/{name}' for name in
                ('libduanju_core.so', 'libflutter.so', 'libapp.so', 'libmpv.so', 'libffmpegkit.so')}
    if required - names or any(name.startswith(('lib/armeabi-v7a/', 'lib/x86_64/')) for name in names):
        raise SystemExit('APK 原生库或 ABI 不匹配')
    print(f'{apk.name}: 签名、应用 ID、版本、名称、arm64 原生库和 SHA-256 均匹配')


if __name__ == '__main__':
    main()
