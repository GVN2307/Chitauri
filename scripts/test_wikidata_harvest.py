import requests
import time

langs = {
    "telugu": "wd:Q8097",
    "tamil": "wd:Q5885",
    "malayalam": "wd:Q36236",
    "kannada": "wd:Q33673",
    "hindi": "wd:Q1568"
}
headers = {"User-Agent": "ChitauriMusicBot/1.0 (https://github.com/GVN2307/Chitauri)"}

for name, qid in langs.items():
    t0 = time.time()
    query = f"""
    SELECT ?movieLabel ?year ?composerLabel ?wikiTitle WHERE {{
      ?movie wdt:P31 wd:Q11424 ;
             wdt:P364 {qid} ;
             wdt:P577 ?pubDate .
      BIND(YEAR(?pubDate) AS ?year)
      FILTER(?year >= 1970 && ?year <= 2026)
      OPTIONAL {{ ?movie wdt:P86 ?composer . }}
      OPTIONAL {{
        ?sitelink schema:about ?movie ;
                  schema:isPartOf <https://en.wikipedia.org/> ;
                  schema:name ?wikiTitle .
      }}
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en" . }}
    }}
    """
    try:
        r = requests.get("https://query.wikidata.org/sparql", params={"query": query, "format": "json"}, headers=headers, timeout=60)
        t1 = time.time()
        if r.status_code == 200:
            rows = r.json()["results"]["bindings"]
            print(f"[{name.upper()}] Fetched {len(rows)} real film records in {t1 - t0:.2f}s")
        else:
            print(f"[{name.upper()}] HTTP Error {r.status_code}")
    except Exception as e:
        print(f"[{name.upper()}] Exception: {e}")
