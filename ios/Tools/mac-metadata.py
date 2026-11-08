#!/usr/bin/env python3
"""Sync Mac-only version text without overwriting shared iOS app information."""
import argparse
import json
from pathlib import Path
import subprocess


def asc(*args):
    return json.loads(subprocess.check_output(['asc', *args, '--output', 'json'], text=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version-id', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    version = asc('versions', 'view', '--version-id', args.version_id, '--include', 'build')
    if version['data']['attributes']['platform'] != 'MAC_OS':
        parser.error('Refusing to update a non-Mac version')
    root = Path(__file__).resolve().parents[1] / 'fastlane/mac-metadata'
    locales = asc('localizations', 'list', '--version', args.version_id, '--paginate')['data']
    changes = []
    for loc in locales:
        locale = loc['attributes']['locale']
        folder = root / locale
        description = (folder / 'description.txt').read_text().strip()
        keywords = (folder / 'keywords.txt').read_text().strip()
        if not description or len(description) > 4000 or len(keywords) > 100:
            raise ValueError(f'Invalid metadata for {locale}')
        changes.append((locale, loc['id'], description, keywords))
    notes = (root / 'review-notes.txt').read_text().strip()
    if not notes or len(notes) > 4000:
        raise ValueError('Invalid review notes')
    review = asc('review', 'details-for-version', '--version-id', args.version_id)
    for locale, loc_id, description, keywords in changes:
        if args.apply:
            asc('localizations', 'update', '--id', loc_id, '--description', description, '--keywords', keywords)
        print(('Updated ' if args.apply else 'Would update ') + locale)
    if args.apply:
        asc('review', 'details-update', '--id', review['data']['id'], '--notes', notes,
            '--demo-account-required=false')
    print(('Updated' if args.apply else 'Would update') + ' Mac review notes; shared app info untouched')


if __name__ == '__main__':
    main()
