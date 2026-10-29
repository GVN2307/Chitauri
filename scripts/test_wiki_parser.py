import requests
import re

def parse_wiki_year_table(title, year, lang):
    url = 'https://en.wikipedia.org/w/api.php'
    params = {
        'action': 'query',
        'prop': 'revisions',
        'titles': title,
        'rvprop': 'content',
        'format': 'json'
    }
    headers = {'User-Agent': 'ChitauriMusicBot/1.0'}
    r = requests.get(url, params=params, headers=headers).json()
    pages = r['query']['pages']
    content = list(pages.values())[0].get('revisions', [{}])[0].get('*', '')
    
    films = []
    # Match wiki table rows
    rows = content.split('|-')
    for row in rows:
        lines = [line.strip() for line in row.split('\n') if line.strip()]
        if not lines:
            continue
        # Join lines or split by ||
        full_row = ' '.join(lines)
        if "''" in full_row or '[[' in full_row:
            parts = re.split(r'\|\||(?<=\n)\|', full_row)
            if len(parts) >= 3:
                # First part usually has title
                title_match = re.search(r"''\[\[([^\|\]]+)(?:\|([^\]]+))?\]\]''|\[\[([^\|\]]+)(?:\|([^\]]+))?\]\]|''([^']+)''", parts[0])
                if title_match:
                    film_title = title_match.group(2) or title_match.group(1) or title_match.group(4) or title_match.group(3) or title_match.group(5)
                    # Look for composer in later columns
                    composer = ""
                    for part in parts[2:]:
                        comp_match = re.search(r'\[\[([^\|\]]+)(?:\|([^\]]+))?\]\]', part)
                        if comp_match:
                            candidate = comp_match.group(2) or comp_match.group(1)
                            if any(k in candidate.lower() for k in ['raaja', 'rahman', 'sharma', 'prasad', 'keeravani', 'chakravarthy', 'thaman', 'kumar', 'singh', 'burman', 'lahiri', 'viswanathan', 'johnson', 'hamsalekha']):
                                composer = candidate
                                break
                    films.append({'title': film_title.strip(), 'composer': composer, 'year': year, 'lang': lang})
    return films

test_films = parse_wiki_year_table('List of Telugu films of 1990', 1990, 'telugu')
print(f'Extracted {len(test_films)} films from List of Telugu films of 1990:')
for f in test_films[:10]:
    print('  ', f)
