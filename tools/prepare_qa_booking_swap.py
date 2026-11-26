#!/usr/bin/env python3
"""Prepare and rehearse an offline Booking-only swap; never deploy it."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

from prepare_booking_qa import BOOKING_PATH, check as check_booking
from prepare_marketing_release import PreparationError, inventory
from qa_artifact_integrity import MANIFEST, comparison_input, create, verify

BOOKING_DIR = BOOKING_PATH.strip('/')


def verified_files(root, digest, label):
    report = verify(root, digest)
    if any(report[key] for key in ('missing', 'unexpected', 'changed')):
        raise PreparationError(f'{label} differs from its pinned inventory')
    files, _ = comparison_input(root / MANIFEST, digest, None)
    return files


def prepare(*, baseline, baseline_digest, booking, booking_digest, output):
    baseline, booking, output = map(Path, (baseline, booking, output))
    if output.exists() or output.is_symlink():
        raise PreparationError('Output must be a new directory')
    location = output.resolve()
    for source in (baseline.resolve(), booking.resolve()):
        if location == source or source in location.parents:
            raise PreparationError('Output must be outside both inputs')

    baseline_files = verified_files(baseline, baseline_digest, 'Preview baseline')
    booking_files = verified_files(booking, booking_digest, 'Booking build')
    check_booking(booking)
    prefix = BOOKING_DIR + '/'
    preserved = {name: entry for name, entry in baseline_files.items() if not name.startswith(prefix)}
    if len(preserved) == len(baseline_files) or 'app/index.html' not in preserved:
        raise PreparationError('Preview baseline must contain both the main and Booking portals')
    expected = {**preserved, **{prefix + name: entry for name, entry in booking_files.items()}}

    with tempfile.TemporaryDirectory(prefix='.booking-rehearsal-', dir=output.parent) as tmp:
        work = Path(tmp)
        result = work / 'result'
        result.mkdir()
        rollback = result / 'rollback'
        candidate = result / 'candidate'
        shutil.copytree(baseline, rollback)
        verified_files(rollback, baseline_digest, 'Rollback copy')

        shutil.copytree(rollback, candidate)
        (candidate / MANIFEST).unlink()
        shutil.rmtree(candidate / BOOKING_DIR)
        shutil.copytree(booking, candidate / BOOKING_DIR)
        (candidate / BOOKING_DIR / MANIFEST).unlink()
        if inventory(candidate) != expected:
            raise PreparationError('Staged candidate differs from its exact component inventories')
        check_booking(candidate / BOOKING_DIR)
        candidate_receipt = create(candidate)
        verified_files(candidate, candidate_receipt['manifest_sha256'], 'Rehearsal candidate')

        # Recreate the previous preview in a separate blank location.
        restored = work / 'restored'
        shutil.copytree(rollback, restored)
        verified_files(restored, baseline_digest, 'Recreated preview')
        receipt = {
            'mode': 'offline-booking-swap-rehearsal',
            'deployment_authorized': False,
            'source_identity_verified': False,
            'baseline_manifest_sha256': baseline_digest,
            'booking_manifest_sha256': booking_digest,
            'candidate_manifest_sha256': candidate_receipt['manifest_sha256'],
            'files_outside_booking_unchanged': len(preserved),
            'candidate_files': len(expected),
            'rollback_files_recreated': len(baseline_files),
        }
        (result / 'receipt.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
        if output.exists() or output.is_symlink():
            raise PreparationError('Output appeared during rehearsal')
        result.rename(output)
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--baseline-sha256', required=True)
    parser.add_argument('--booking', required=True)
    parser.add_argument('--booking-sha256', required=True)
    parser.add_argument('--out', required=True)
    args = parser.parse_args(argv)
    try:
        result = prepare(baseline=args.baseline, baseline_digest=args.baseline_sha256,
                         booking=args.booking, booking_digest=args.booking_sha256,
                         output=args.out)
        print(json.dumps(result, sort_keys=True))
    except (OSError, ValueError, TypeError, KeyError) as error:
        parser.exit(1, f'FAIL: {error}\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
