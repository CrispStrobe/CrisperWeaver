#!/usr/bin/env python3
"""Distribute exact iOS/macOS builds; external review submission is not approval.

Requires PyJWT[crypto]==2.10.1. Credentials are read from the key file/env;
tokens and private keys are never printed. --inspect makes no changes.
"""
import argparse
import json
import os
from pathlib import Path
import time
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import jwt


class Apple:
    def __init__(self, key, key_id, issuer):
        self.key, self.key_id, self.issuer = key, key_id, issuer

    def call(self, method, path, data=None, params=None):
        now = int(time.time())
        token = jwt.encode({'iss': self.issuer, 'iat': now, 'exp': now + 600,
                            'aud': 'appstoreconnect-v1'}, self.key, algorithm='ES256',
                           headers={'kid': self.key_id, 'typ': 'JWT'})
        url = 'https://api.appstoreconnect.apple.com/v1/' + path
        if params:
            url += '?' + urlencode(params)
        req = Request(url, method=method,
                      data=None if data is None else json.dumps(data).encode(),
                      headers={'Authorization': 'Bearer ' + token,
                               'Content-Type': 'application/json'})
        try:
            with urlopen(req, timeout=60) as response:
                body = response.read()
                return json.loads(body) if body else {}
        except HTTPError as e:
            # Apple JSON errors contain resource diagnostics, never our headers.
            raise RuntimeError(f'{method} {path}: HTTP {e.code}: '
                               f'{e.read().decode()[:2000]}') from None


def select_builds(document, version, build):
    included = {x['id']: x for x in document.get('included', [])}
    selected = {}
    for item in document['data']:
        if item['attributes']['version'] != build:
            continue
        ref = item['relationships']['preReleaseVersion'].get('data')
        pre = included.get(ref['id'] if ref else '', {}).get('attributes', {})
        platform = pre.get('platform')
        if pre.get('version') != version or platform not in ('IOS', 'MAC_OS'):
            continue
        if platform in selected:
            raise RuntimeError(f'Ambiguous {platform} build {version} ({build})')
        if item['attributes']['processingState'] in ('FAILED', 'INVALID'):
            raise RuntimeError(f'{platform} build processing failed')
        selected[platform] = item
    return selected


def distribute(api, item, groups, notes):
    bid = item['id']
    localizations = api.call('GET', f'builds/{bid}/betaBuildLocalizations')['data']
    for locale, text in notes.items():
        existing = next((x for x in localizations if x['attributes']['locale'] == locale), None)
        attrs = {'whatsNew': text}
        if existing:
            api.call('PATCH', 'betaBuildLocalizations/' + existing['id'],
                     {'data': {'type': 'betaBuildLocalizations', 'id': existing['id'],
                               'attributes': attrs}})
        else:
            api.call('POST', 'betaBuildLocalizations',
                     {'data': {'type': 'betaBuildLocalizations',
                               'attributes': {'locale': locale, **attrs},
                               'relationships': {'build': {'data': {'type': 'builds', 'id': bid}}}}})
    detail = api.call('GET', f'builds/{bid}/buildBetaDetail')['data']
    api.call('PATCH', 'buildBetaDetails/' + detail['id'],
             {'data': {'type': 'buildBetaDetails', 'id': detail['id'],
                       'attributes': {'autoNotifyEnabled': True}}})
    assigned = api.call('GET', f'builds/{bid}/relationships/betaGroups')['data']
    missing = [{'type': 'betaGroups', 'id': g['id']} for g in groups
               if g['id'] not in {x['id'] for x in assigned}]
    if missing:
        api.call('POST', f'builds/{bid}/relationships/betaGroups', {'data': missing})
    detail = api.call('GET', f'builds/{bid}/buildBetaDetail')['data']
    state = detail['attributes']['externalBuildState']
    if state == 'READY_FOR_BETA_SUBMISSION':
        api.call('POST', 'betaAppReviewSubmissions',
                 {'data': {'type': 'betaAppReviewSubmissions',
                           'relationships': {'build': {'data': {'type': 'builds', 'id': bid}}}}})
    elif state not in ('WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW',
                       'BETA_APPROVED', 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'):
        raise RuntimeError(f'Unexpected external state {state}; inspect Apple review requirements')
    detail = api.call('GET', f'builds/{bid}/buildBetaDetail')['data']['attributes']
    assigned = api.call('GET', f'builds/{bid}/relationships/betaGroups')['data']
    if not {g['id'] for g in groups}.issubset({g['id'] for g in assigned}):
        raise RuntimeError('Tester group assignment did not persist')
    return {'buildId': bid, 'groups': [g['attributes']['name'] for g in groups], **detail}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--app', default=os.environ.get('APPSTORE_APP_ID') or '6789600762')
    parser.add_argument('--key', type=Path, default=Path.home() / '.appstoreconnect/private_keys/AuthKey_9RMU3C7422.p8')
    parser.add_argument('--key-id', default='9RMU3C7422')
    parser.add_argument('--issuer', default='5f618ba3-98ef-42ad-835c-fbbef6c76cf5')
    parser.add_argument('--notes', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--wait-seconds', type=int, default=5400)
    parser.add_argument('--inspect', action='store_true')
    args = parser.parse_args()
    if not args.inspect and not args.notes:
        parser.error('--notes JSON locale-to-text mapping is required for distribution')
    api = Apple(args.key.read_text(), args.key_id, args.issuer)
    groups = api.call('GET', f'apps/{args.app}/betaGroups', params={'limit': 200})['data']
    groups = [g for g in groups if g['attributes']['name'] in ('Internal', 'External Testers')]
    if (len(groups) != 2 or
            {g['attributes']['isInternalGroup'] for g in groups} != {True, False}):
        raise RuntimeError('Expected existing Internal and External Testers groups')
    deadline = time.monotonic() + args.wait_seconds
    while True:
        document = api.call('GET', 'builds', params={'filter[app]': args.app,
                            'filter[version]': args.build, 'limit': 200,
                            'include': 'preReleaseVersion,buildBetaDetail'})
        builds = select_builds(document, args.version, args.build)
        ready = (set(builds) == {'IOS', 'MAC_OS'} and
                 all(x['attributes']['processingState'] == 'VALID' for x in builds.values()))
        if args.inspect or ready:
            break
        if time.monotonic() >= deadline:
            raise TimeoutError('Both exact iOS/macOS builds did not become VALID')
        print('Waiting for Apple processing of both exact builds:',
              {k: b['attributes']['processingState'] for k, b in builds.items()}, flush=True)
        time.sleep(min(30, max(0, deadline - time.monotonic())))
    results = {}
    for platform, item in builds.items():
        if args.inspect:
            results[platform] = {'buildId': item['id'], **item['attributes'],
                                **api.call('GET', f'builds/{item["id"]}/buildBetaDetail')['data']['attributes']}
        else:
            notes = json.loads(args.notes.read_text())
            if not notes or not all(isinstance(v, str) and v.strip() for v in notes.values()):
                raise ValueError('Beta notes must contain nonempty text')
            results[platform] = distribute(api, item, groups, notes)
        print(platform, json.dumps(results[platform], ensure_ascii=False), flush=True)
        if args.output:
            args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2))
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as f:
            f.write(f'\n### TestFlight {args.version} ({args.build})\n\n')
            for platform, result in results.items():
                f.write(f'- {platform}: internal `{result["internalBuildState"]}`, external '
                        f'`{result["externalBuildState"]}`\n')
            f.write('\nExternal review submission is not approval or availability.\n')


if __name__ == '__main__':
    main()
