#!/usr/bin/env python3
"""Select/create a separate Lite project using CI's existing Vercel token."""
import json
import os
import urllib.error
import urllib.parse
import urllib.request

name = 'crisperweaver-lite-web'
token = os.environ['VERCEL_TOKEN']
org = os.environ['VERCEL_ORG_ID']
if not token or not org:
    raise SystemExit('Existing VERCEL_TOKEN and VERCEL_ORG_ID secrets are required')
query = '?' + urllib.parse.urlencode({'teamId': org}) if org.startswith('team_') else ''


def request(path, data=None):
    req = urllib.request.Request('https://api.vercel.com' + path + query,
        headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'},
        data=None if data is None else json.dumps(data).encode())
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.load(res)


try:
    project = request('/v9/projects/' + name)
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise SystemExit(f'Cannot read Lite Vercel project: HTTP {error.code}') from None
    project = request('/v11/projects', {'name': name, 'framework': None,
        'buildCommand': None, 'outputDirectory': '.', 'skipGitConnectDuringLink': True})
if project['id'] == os.environ.get('VERCEL_PROJECT_ID'):
    raise SystemExit('Refusing to deploy Lite over the full web project')
if project['name'] != name or project['accountId'] != org:
    raise SystemExit('Unexpected Lite project name or account')
with open(os.environ['GITHUB_ENV'], 'a') as env:
    env.write('VERCEL_PROJECT_ID=' + project['id'] + '\n')
print('Selected separate Vercel project:', name)
