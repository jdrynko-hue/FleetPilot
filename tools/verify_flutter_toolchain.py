"""Fail a QA build when its Flutter/Dart toolchain differs from the reviewed pin."""
import argparse
import json
from pathlib import Path
import sys

PIN = Path(__file__).resolve().parents[1] / 'tool/flutter-toolchain.json'
FIELDS = {'frameworkVersion', 'channel', 'frameworkRevision', 'engineRevision', 'dartSdkVersion'}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate toolchain key')
        result[key] = value
    return result


def compare(actual, expected):
    if (not isinstance(expected, dict) or set(expected) != FIELDS
            or any(not isinstance(v, str) or not v for v in expected.values())):
        raise ValueError('Invalid reviewed toolchain pin')
    if not isinstance(actual, dict):
        raise ValueError('Invalid Flutter machine output')
    # Ignore host-specific paths and informational timestamps, not SDK identity.
    return sorted(key for key in FIELDS if actual.get(key) != expected[key])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actual', type=Path, required=True)
    args = parser.parse_args()
    try:
        expected = json.loads(PIN.read_text(), object_pairs_hook=unique_object)
        actual = json.loads(args.actual.read_text(), object_pairs_hook=unique_object)
        differences = compare(actual, expected)
        if differences:
            raise ValueError('Toolchain mismatch: ' + ', '.join(differences))
        print('PASS: reviewed Flutter framework, engine and Dart SDK identities')
        return 0
    except (OSError, ValueError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
