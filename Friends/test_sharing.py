"""Exercise the deployed rules in the Firebase Auth and Database emulators."""
import json
import os
import time
import urllib.error
import urllib.request
import uuid

auth = os.environ['FIREBASE_AUTH_EMULATOR_HOST']
database = os.environ['FIREBASE_DATABASE_EMULATOR_HOST']
def request(method, url, body=None, allowed=True):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as response:
            assert allowed, 'unexpected success'
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if allowed or exc.code not in (401, 403):
            raise

def account():
    return request('POST', f'http://{auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test', {'returnSecureToken': True})

def db(who, method, path, body=None, allowed=True):
    return request(method, f'http://{database}/{path}.json?ns=demo-dotlings-default-rtdb&auth={who["idToken"]}', body, allowed)

a, b, c = account(), account(), account()
owner, reader, outsider = (x['localId'] for x in (a,b,c))
p = f'people/{owner}'
key = uuid.uuid4().hex
link = f'{p}/passes/{key}'
mood = dict(ownerName='Alice', petName='Mocha', kind='coffee', mood='happy', updatedAt=100)
db(a, 'PUT', p+'/mood', mood)
db(a, 'PUT', link, {'expires': int(time.time()*1000)+100000})
db(c, 'GET', p+'/passes', allowed=False)
db(b, 'GET', p+'/mood', allowed=False)
db(c, 'PUT', f'{p}/grants/{outsider}', key, allowed=False)
db(b, 'PUT', link+'/reader', reader)
db(c, 'PUT', link+'/reader', outsider, allowed=False)
db(b, 'PUT', f'{p}/grants/{reader}', key)
db(b, 'PUT', f'following/{reader}/{owner}', True)
assert db(b,'GET',p+'/mood') == mood
mood['mood']='calm'
db(a,'PUT',p+'/mood',mood)
assert db(b,'GET',p+'/mood')['mood']=='calm'
db(b,'PUT',p+'/mood',mood,False)
db(c,'GET',p+'/mood',allowed=False)
db(a,'DELETE',link)
db(b,'GET',p+'/mood',allowed=False)
db(a,'PUT',link,{'expires':1})
db(c,'PUT',link+'/reader',outsider,False)
print('Three anonymous identities: private sharing, single use, expiry, live updates and revocation passed.')
