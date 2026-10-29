import requests

url = 'https://en.wikipedia.org/w/api.php'
params = {
    'action': 'query',
    'list': 'search',
    'srsearch': 'intitle:"List of Telugu films of"',
    'srlimit': 50,
    'format': 'json'
}
headers = {'User-Agent': 'ChitauriMusicBot/1.0'}
r = requests.get(url, params=params, headers=headers).json()
print('Total search matches:', r['query']['searchinfo']['totalhits'])
for item in r['query']['search'][:10]:
    print('  ', item['title'])
