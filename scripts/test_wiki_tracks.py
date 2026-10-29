import requests
import re

url = 'https://en.wikipedia.org/w/api.php'
films = [
    'Sankarabharanam (1980 film)', 'Aditya 369', 'Kshana Kshanam', 'Okkadu', 'Athadu', 'Jalsa', 'RRR (soundtrack)',
    'Thalapathi', 'Roja (soundtrack)', 'Bombay (soundtrack)', 'Minnale', 'Ghajini (2005 film)', 'Jailer (film)',
    'Premam (2015 film)', 'His Highness Abdullah', 'Summer in Bethlehem', 'Hridayam',
    'Mungaru Male', 'KGF: Chapter 1', 'Kantara (film)',
    'Dilwale Dulhania Le Jayenge', 'Kal Ho Naa Ho', 'Jab We Met', 'Aashiqui 2'
]
params = {
    'action': 'query',
    'prop': 'revisions',
    'titles': '|'.join(films),
    'rvprop': 'content',
    'format': 'json'
}
headers = {'User-Agent': 'ChitauriMusicBot/1.0'}
r = requests.get(url, params=params, headers=headers).json()
pages = r['query']['pages']
total_songs = 0
for pid, p in pages.items():
    title = p['title']
    content = p.get('revisions', [{}])[0].get('*', '')
    tracks = re.findall(r'\|\s*title\d*\s*=\s*"?([^"\n\|\}]+)', content)
    if tracks:
        clean_tracks = [re.sub(r'\[\[|\]\]', '', t).split('|')[-1].strip() for t in tracks if len(t.strip()) > 2]
        total_songs += len(clean_tracks)
        print(f'{title} -> {len(clean_tracks)} songs: {clean_tracks[:3]}')
print(f'Total songs extracted: {total_songs}')
