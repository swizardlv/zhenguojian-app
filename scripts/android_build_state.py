import json
import os
import re
import tempfile
from pathlib import Path


ABI_VERSION_CODE_OFFSETS = {
    'armeabi-v7a': 1000,
    'arm64-v8a': 2000,
    'x86_64': 3000,
}
MAX_ANDROID_VERSION_CODE = 2_147_483_647
STATE_FILENAME = 'android-version-state.json'
LOCK_FILENAME = 'android-version-state.lock'
VALID_VARIANTS = {'hongguojian', 'zhenguojian'}


def pubspec_build_number(pubspec_path):
    text = Path(pubspec_path).read_text(encoding='utf-8')
    match = re.search(r'(?m)^version:\s*[^\s+]+\+(\d+)\s*$', text)
    if not match:
        raise ValueError(
            'pubspec.yaml must define a numeric version build number, '
            'for example 0.2.56+62.'
        )
    return int(match.group(1))


def _empty_state(initial_build_number):
    return {
        'last_build_number': initial_build_number,
        'last_version_code': 0,
        'outputs': {},
    }


def _read_state(path, initial_build_number):
    if not path.exists():
        return _empty_state(initial_build_number)
    try:
        state = json.loads(path.read_text(encoding='utf-8'))
        last_build_number = state['last_build_number']
        last_version_code = state['last_version_code']
        outputs = state['outputs']
        if (
            type(last_build_number) is not int
            or last_build_number < 0
            or type(last_version_code) is not int
            or not 0 <= last_version_code <= MAX_ANDROID_VERSION_CODE
            or not isinstance(outputs, dict)
        ):
            raise ValueError
        for variant, variant_outputs in outputs.items():
            if variant not in VALID_VARIANTS or not isinstance(variant_outputs, dict):
                raise ValueError
            for abi, version_code in variant_outputs.items():
                if (
                    abi not in ABI_VERSION_CODE_OFFSETS
                    or type(version_code) is not int
                    or not 0 < version_code <= MAX_ANDROID_VERSION_CODE
                ):
                    raise ValueError
        return {
            'last_build_number': last_build_number,
            'last_version_code': max(
                last_version_code,
                *(
                    code
                    for outputs_for_variant in outputs.values()
                    for code in outputs_for_variant.values()
                ),
            ),
            'outputs': outputs,
        }
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        raise ValueError(f'Android build version state is invalid: {path}') from error


def _lock(stream):
    if os.name == 'nt':
        import msvcrt

        stream.seek(0, os.SEEK_END)
        if stream.tell() == 0:
            stream.write(b'\0')
            stream.flush()
        stream.seek(0)
        msvcrt.locking(stream.fileno(), msvcrt.LK_LOCK, 1)
        return
    import fcntl

    fcntl.flock(stream.fileno(), fcntl.LOCK_EX)


def _unlock(stream):
    if os.name == 'nt':
        import msvcrt

        stream.seek(0)
        msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        return
    import fcntl

    fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


class AndroidBuildVersion:
    def __init__(self, metadata_directory, pubspec_path, variant_slug, abis):
        self.metadata_directory = Path(metadata_directory)
        self.pubspec_path = Path(pubspec_path)
        self.variant_slug = variant_slug
        self.abis = tuple(dict.fromkeys(abis))
        if variant_slug not in VALID_VARIANTS:
            raise ValueError(f'Unsupported Android product variant: {variant_slug}')
        if not self.abis:
            raise ValueError('At least one Android ABI must be selected.')
        unknown = set(self.abis) - ABI_VERSION_CODE_OFFSETS.keys()
        if unknown:
            raise ValueError('Unsupported Android ABI: ' + ', '.join(sorted(unknown)))
        self.state_path = self.metadata_directory / STATE_FILENAME
        self.lock_path = self.metadata_directory / LOCK_FILENAME
        self._lock_stream = None
        self._lock_acquired = False
        self._state = None
        self._committed = False

    def __enter__(self):
        self.metadata_directory.mkdir(parents=True, exist_ok=True)
        self._lock_stream = self.lock_path.open('a+b')
        try:
            _lock(self._lock_stream)
            self._lock_acquired = True
            baseline = pubspec_build_number(self.pubspec_path)
            self._state = _read_state(self.state_path, baseline)
            lowest_abi_offset = min(ABI_VERSION_CODE_OFFSETS[abi] for abi in self.abis)
            self.build_number = max(
                baseline + 1,
                self._state['last_build_number'] + 1,
                self._state['last_version_code'] - lowest_abi_offset + 1,
            )
            highest_abi_offset = max(ABI_VERSION_CODE_OFFSETS[abi] for abi in self.abis)
            if self.build_number + highest_abi_offset > MAX_ANDROID_VERSION_CODE:
                raise ValueError('The next Android versionCode would exceed the Android integer limit.')
            return self
        except BaseException:
            self._close_lock()
            raise

    def __exit__(self, exception_type, exception, traceback):
        self._close_lock()
        return False

    def _close_lock(self):
        if self._lock_stream is None:
            return
        stream = self._lock_stream
        self._lock_stream = None
        try:
            if self._lock_acquired:
                _unlock(stream)
        finally:
            self._lock_acquired = False
            stream.close()

    def version_code(self, abi):
        if abi not in self.abis:
            raise ValueError(f'ABI was not selected for this build: {abi}')
        return self.build_number + ABI_VERSION_CODE_OFFSETS[abi]

    def commit(self):
        if self._lock_stream is None:
            raise RuntimeError('Android build version lock is not held.')
        if self._committed:
            raise RuntimeError('Android build version state was already committed.')
        outputs = {
            variant: dict(variant_outputs)
            for variant, variant_outputs in self._state['outputs'].items()
        }
        variant_outputs = outputs.setdefault(self.variant_slug, {})
        for abi in self.abis:
            variant_outputs[abi] = self.version_code(abi)
        last_version_code = max(
            self._state['last_version_code'],
            *(self.version_code(abi) for abi in self.abis),
        )
        state = {
            'last_build_number': self.build_number,
            'last_version_code': last_version_code,
            'outputs': outputs,
        }
        temporary_name = None
        try:
            with tempfile.NamedTemporaryFile(
                mode='w',
                encoding='utf-8',
                newline='\n',
                prefix=self.state_path.name + '.',
                suffix='.tmp',
                dir=self.metadata_directory,
                delete=False,
            ) as stream:
                temporary_name = stream.name
                json.dump(state, stream, sort_keys=True, separators=(',', ':'))
                stream.write('\n')
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary_name, self.state_path)
            temporary_name = None
            if os.name != 'nt':
                try:
                    directory_fd = os.open(self.metadata_directory, os.O_RDONLY)
                    try:
                        os.fsync(directory_fd)
                    finally:
                        os.close(directory_fd)
                except OSError:
                    pass
        finally:
            if temporary_name is not None:
                Path(temporary_name).unlink(missing_ok=True)
        self._committed = True


def recorded_build(metadata_directory, variant_slug, abi):
    if variant_slug not in VALID_VARIANTS:
        raise ValueError(f'Unsupported Android product variant: {variant_slug}')
    if abi not in ABI_VERSION_CODE_OFFSETS:
        raise ValueError(f'Unsupported Android ABI: {abi}')
    state_path = Path(metadata_directory) / STATE_FILENAME
    if not state_path.is_file():
        return None
    state = _read_state(state_path, 0)
    version_code = state['outputs'].get(variant_slug, {}).get(abi)
    if version_code is None:
        return None
    return version_code - ABI_VERSION_CODE_OFFSETS[abi], version_code
