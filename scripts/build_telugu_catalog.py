#!/usr/bin/env python3
"""
Generates sharded Telugu Movie Song JSON files (1970s-2020s) for GitHub Pages or CDN hosting.
Usage:
  pip install requests
  python build_telugu_catalog.py
"""

import hashlib
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Set, Tuple
import requests

OUTPUT_DIR = Path("catalog")
DECADES = ["1970s", "1980s", "1990s", "2000s", "2010s", "2020s"]

# Canonical Telugu Composers by Era to enrich iTunes queries & normalize names
CANONICAL_COMPOSERS = [
    "K. V. Mahadevan", "S. Rajeswara Rao", "Pendyaala Nageswara Rao", "Ramesh Naidu",
    "K. Chakravarthy", "Satyam", "Rajan-Nagendra", "Ilaiyaraaja", "M. M. Keeravani",
    "Raj-Koti", "Koti", "Mani Sharma", "S. V. Krishna Reddy", "Vandemataram Srinivas",
    "Ramana Gogula", "R. P. Patnaik", "Devi Sri Prasad", "Chakri", "Harris Jayaraj",
    "Kalyani Malik", "Yuvan Shankar Raja", "Mickey J. Meyer", "A. R. Rahman",
    "Thaman S", "Anup Rubens", "Sunny M.R.", "Gopi Sundar", "Vivek Sagar",
    "Chaitan Bharadwaj", "Kaala Bhairava", "Bheems Ceciroleo", "Hesham Abdul Wahab",
    "Anirudh Ravichander", "G. V. Prakash Kumar"
]

KNOWN_SINGERS = [
    "S. P. Balasubrahmanyam", "P. Susheela", "S. Janaki", "V. Ramakrishna",
    "Ghantasala", "K. J. Yesudas", "K. S. Chithra", "Mano", "S. P. Sailaja",
    "Sujatha Mohan", "Unnikrishnan", "Hariharan", "Shankar Mahadevan", "Udit Narayan",
    "KK", "Karthik", "Shreya Ghoshal", "Sunitha Upadrasta", "Tippu", "Mallikarjun",
    "Gopika Poornima", "Hemachandra", "Geetha Madhuri", "Chinmayi", "Vijay Prakash",
    "Sid Sriram", "Anurag Kulkarni", "Ram Miriyala", "Armaan Malik", "Mangli",
    "Haricharan", "Rahul Sipligunj", "Kaala Bhairava", "Shweta Mohan", "Jonita Gandhi"
]

# Evergreen Baseline Seed (Ensures iconic hits across all 6 decades are always present)
EVERGREEN_SEED: List[Dict] = [
    # 1970s
    {"title": "Omkaara Naadaanusandhaanamou", "movie": "Sankarabharanam", "year": 1980, "decade": "1970s", "composer": "K. V. Mahadevan", "singers": ["S. P. Balasubrahmanyam", "S. Janaki"], "mood": "Classical", "popularity": 98},
    {"title": "RaaVoyi Chandamama", "movie": "Missamma", "year": 1971, "decade": "1970s", "composer": "S. Rajeswara Rao", "singers": ["Ghantasala", "P. Susheela"], "mood": "Melody", "popularity": 94},
    {"title": "Jhummandi Naadam", "movie": "Siri Siri Muvva", "year": 1976, "decade": "1970s", "composer": "K. V. Mahadevan", "singers": ["S. P. Balasubrahmanyam", "P. Susheela"], "mood": "Classical", "popularity": 96},
    {"title": "Siva Sankari", "movie": "Jagadeka Veeruni Katha", "year": 1972, "decade": "1970s", "composer": "Pendyala Nageswara Rao", "singers": ["Ghantasala"], "mood": "Classical", "popularity": 95},
    {"title": "Aakulo Aakunai", "movie": "Megha Sandesam", "year": 1979, "decade": "1970s", "composer": "Ramesh Naidu", "singers": ["K. J. Yesudas", "P. Susheela"], "mood": "Melody", "popularity": 93},
    # 1980s
    {"title": "Maate Mantramu", "movie": "Seethakoka Chiluka", "year": 1981, "decade": "1980s", "composer": "Ilaiyaraaja", "singers": ["S. P. Balasubrahmanyam", "S. P. Sailaja"], "mood": "Melody", "popularity": 97},
    {"title": "Takita Tadimi", "movie": "Sagara Sangamam", "year": 1983, "decade": "1980s", "composer": "Ilaiyaraaja", "singers": ["S. P. Balasubrahmanyam"], "mood": "Classical", "popularity": 99},
    {"title": "Suvvi Suvvi Suvvalamma", "movie": "Swathi Muthyam", "year": 1986, "decade": "1980s", "composer": "Ilaiyaraaja", "singers": ["S. P. Balasubrahmanyam", "S. Janaki"], "mood": "Melody", "popularity": 96},
    {"title": "Aamani Paadave", "movie": "Geethanjali", "year": 1989, "decade": "1980s", "composer": "Ilaiyaraaja", "singers": ["S. P. Balasubrahmanyam"], "mood": "Melody", "popularity": 99},
    {"title": "Keeravani Raagamlo", "movie": "Anveshana", "year": 1985, "decade": "1980s", "composer": "Ilaiyaraaja", "singers": ["S. P. Balasubrahmanyam", "S. Janaki"], "mood": "Melody", "popularity": 97},
    # 1990s
    {"title": "Jaanavule Nerajaanavule", "movie": "Aditya 369", "year": 1991, "decade": "1990s", "composer": "Ilaiyaraaja", "singers": ["S. P. Balasubrahmanyam", "Jikki"], "mood": "Melody", "popularity": 96},
    {"title": "Jaamu Raathiri", "movie": "Kshana Kshanam", "year": 1991, "decade": "1990s", "composer": "M. M. Keeravani", "singers": ["S. P. Balasubrahmanyam", "K. S. Chithra"], "mood": "Melody", "popularity": 98},
    {"title": "Telusa Manasa", "movie": "Criminal", "year": 1995, "decade": "1990s", "composer": "M. M. Keeravani", "singers": ["S. P. Balasubrahmanyam", "K. S. Chithra"], "mood": "Romantic", "popularity": 97},
    {"title": "Premante Suluvukadura", "movie": "Kushi", "year": 1999, "decade": "1990s", "composer": "Mani Sharma", "singers": ["Devan Ekambaram", "Kalpana"], "mood": "Melody", "popularity": 95},
    {"title": "Priya Priyathama", "movie": "Killer", "year": 1991, "decade": "1990s", "composer": "Ilaiyaraaja", "singers": ["Mano", "K. S. Chithra"], "mood": "Romantic", "popularity": 95},
    # 2000s
    {"title": "Cheppave Chirugali", "movie": "Okkadu", "year": 2003, "decade": "2000s", "composer": "Mani Sharma", "singers": ["Udit Narayan", "Sujatha Mohan"], "mood": "Melody", "popularity": 99},
    {"title": "Pilichina Ranantava", "movie": "Athadu", "year": 2005, "decade": "2000s", "composer": "Mani Sharma", "singers": ["Karthik", "Kavita Krishnamurthy"], "mood": "Melody", "popularity": 98},
    {"title": "Nuvvostanante Nenoddantana", "movie": "Nuvvostanante Nenoddantana", "year": 2005, "decade": "2000s", "composer": "Devi Sri Prasad", "singers": ["Shankar Mahadevan", "Gopika Poornima"], "mood": "Melody", "popularity": 97},
    {"title": "My Heart Is Beating", "movie": "Jalsa", "year": 2008, "decade": "2000s", "composer": "Devi Sri Prasad", "singers": ["KK"], "mood": "Romantic", "popularity": 99},
    {"title": "Kotha Bangaru Lokam", "movie": "Kotha Bangaru Lokam", "year": 2008, "decade": "2000s", "composer": "Mickey J. Meyer", "singers": ["Karthik", "Shreya Ghoshal"], "mood": "Melody", "popularity": 96},
    # 2010s
    {"title": "Nee Choopule", "movie": "Endukante Premanta", "year": 2012, "decade": "2010s", "composer": "G. V. Prakash Kumar", "singers": ["Haricharan", "K. S. Chithra"], "mood": "Romantic", "popularity": 96},
    {"title": "Aaradugulauntada", "movie": "Seethamma Vakitlo Sirimalle Chettu", "year": 2013, "decade": "2010s", "composer": "Mickey J. Meyer", "singers": ["Karthik"], "mood": "Melody", "popularity": 96},
    {"title": "Inkem Inkem Inkem Kaavaale", "movie": "Geetha Govindam", "year": 2018, "decade": "2010s", "composer": "Gopi Sundar", "singers": ["Sid Sriram"], "mood": "Romantic", "popularity": 99},
    {"title": "Pilla Raa", "movie": "RX 100", "year": 2018, "decade": "2010s", "composer": "Chaitan Bharadwaj", "singers": ["Anurag Kulkarni"], "mood": "Romantic", "popularity": 97},
    {"title": "Priyathama Priyathama", "movie": "Majili", "year": 2019, "decade": "2010s", "composer": "Gopi Sundar", "singers": ["Chinmayi"], "mood": "Melody", "popularity": 96},
    # 2020s
    {"title": "Samajavaragamana", "movie": "Ala Vaikunthapurramuloo", "year": 2020, "decade": "2020s", "composer": "Thaman S", "singers": ["Sid Sriram"], "mood": "Melody", "popularity": 99},
    {"title": "Butta Bomma", "movie": "Ala Vaikunthapurramuloo", "year": 2020, "decade": "2020s", "composer": "Thaman S", "singers": ["Armaan Malik"], "mood": "Peppy", "popularity": 99},
    {"title": "Srivalli", "movie": "Pushpa: The Rise", "year": 2021, "decade": "2020s", "composer": "Devi Sri Prasad", "singers": ["Sid Sriram"], "mood": "Melody", "popularity": 98},
    {"title": "Naatu Naatu", "movie": "RRR", "year": 2022, "decade": "2020s", "composer": "M. M. Keeravani", "singers": ["Rahul Sipligunj", "Kaala Bhairava"], "mood": "Mass / Folk", "popularity": 99},
    {"title": "Samayama", "movie": "Hi Nanna", "year": 2023, "decade": "2020s", "composer": "Hesham Abdul Wahab", "singers": ["Anurag Kulkarni", "Sithara Krishnakumar"], "mood": "Romantic", "popularity": 98},
    {"title": "Kurchi Madathapetti", "movie": "Guntur Kaaram", "year": 2024, "decade": "2020s", "composer": "Thaman S", "singers": ["Sri Krishna", "Sahithi Chaganti"], "mood": "Mass / Folk", "popularity": 98},
    {"title": "Chuttamalle", "movie": "Devara: Part 1", "year": 2024, "decade": "2020s", "composer": "Anirudh Ravichander", "singers": ["Shilpa Rao"], "mood": "Romantic", "popularity": 99},
]


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())[:14]


def year_to_decade(year: int) -> str:
    if year < 1980:
        return "1970s"
    if year >= 2020:
        return "2020s"
    return f"{(year // 10) * 10}s"


def clean_title_or_movie(raw: str) -> str:
    cleaned = re.sub(r"\s*[\(\[\-].*?(Original Motion Picture|From|Soundtrack|Telugu|OST|Single|EP|Feat).*?[\)\]]?", "", raw, flags=re.IGNORECASE)
    return cleaned.strip(" -–—")


def infer_mood(title: str) -> str:
    lower = title.lower()
    if any(k in lower for k in ["mass", "maar", "naatu", "kurchi", "boss", "party", "dhoom", "pilla"]):
        return "Mass / Folk"
    if any(k in lower for k in ["siva", "om", "raagam", "swara", "govinda", "rama"]):
        return "Classical"
    if any(k in lower for k in ["prema", "love", "hrudayam", "manasa", "priya", "cheliya"]):
        return "Romantic"
    return "Melody"


def fetch_wikidata_telugu_movies() -> Dict[str, Tuple[int, str]]:
    """
    Fetches Telugu movies (1970-2026) with release year and composer from Wikidata SPARQL.
    Returns dict mapping normalized_movie_name -> (year, composer_name).
    """
    print("[1/3] Querying Wikidata SPARQL for Telugu movie release years & composers...")
    sparql_url = "https://query.wikidata.org/sparql"
    query = """
    SELECT ?filmLabel ?year ?composerLabel WHERE {
      ?film wdt:P31 wd:Q11424;
            wdt:P364 wd:Q8097;
            wdt:P577 ?date;
            wdt:P86 ?composer.
      BIND(YEAR(?date) AS ?year)
      FILTER(?year >= 1970 && ?year <= 2026)
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }
    LIMIT 3500
    """
    headers = {"User-Agent": "PulseMP3TeluguCatalogBuilder/2.0 (https://github.com/)"}
    movie_Lookup: Dict[str, Tuple[int, str]] = {}
    try:
        resp = requests.get(sparql_url, params={"query": query, "format": "json"}, headers=headers, timeout=25)
        resp.raise_for_status()
        bindings = resp.json().get("results", {}).get("bindings", [])
        for row in bindings:
            movie_name = row["filmLabel"]["value"]
            year = int(row["year"]["value"])
            composer = row["composerLabel"]["value"]
            movie_Lookup[slugify(movie_name)] = (year, composer)
        print(f"      Loaded {len(movie_Lookup)} authoritative Telugu film records from Wikidata.")
    except Exception as exc:
        print(f"      [Warning] Wikidata query timed out or failed ({exc}); relying on iTunes metadata.")
    return movie_Lookup


def extract_composer_and_singers(artist_str: str, fallback_composer: str) -> Tuple[str, List[str]]:
    parts = [p.strip() for p in re.split(r"[,&/]|feat\.|ft\.", artist_str, flags=re.IGNORECASE) if p.strip()]
    detected_composer = fallback_composer
    singers = []

    for part in parts:
        matched_comp = next((c for c in CANONICAL_COMPOSERS if c.lower() in part.lower()), None)
        if matched_comp and not detected_composer:
            detected_composer = matched_comp
        else:
            singers.append(part)

    if not detected_composer:
        detected_composer = parts[0] if parts else "Various Artists"
    if not singers:
        singers = [parts[-1]] if parts else ["Telugu Playback Singer"]

    return detected_composer, singers[:3]


def harvest_itunes_telugu_songs(wikidata_movies: Dict[str, Tuple[int, str]]) -> List[Dict]:
    """Queries Apple iTunes India API across major Telugu composers and eras."""
    print("[2/3] Harvesting Telugu tracks from Apple iTunes India Search API...")
    search_queries = [
        ("K. V. Mahadevan Telugu", 1976, "K. V. Mahadevan"),
        ("Ramesh Naidu Telugu", 1978, "Ramesh Naidu"),
        ("Chakravarthy Telugu", 1982, "K. Chakravarthy"),
        ("Satyam Telugu songs", 1979, "Satyam"),
        ("Ilaiyaraaja Telugu", 1988, "Ilaiyaraaja"),
        ("Raj Koti Telugu", 1992, "Raj-Koti"),
        ("M. M. Keeravani Telugu", 1996, "M. M. Keeravani"),
        ("Koti Telugu", 1998, "Koti"),
        ("S. V. Krishna Reddy Telugu", 1995, "S. V. Krishna Reddy"),
        ("Mani Sharma Telugu", 2004, "Mani Sharma"),
        ("R. P. Patnaik Telugu", 2002, "R. P. Patnaik"),
        ("Devi Sri Prasad Telugu", 2008, "Devi Sri Prasad"),
        ("Harris Jayaraj Telugu", 2006, "Harris Jayaraj"),
        ("Mickey J. Meyer Telugu", 2010, "Mickey J. Meyer"),
        ("Thaman S Telugu", 2018, "Thaman S"),
        ("Anup Rubens Telugu", 2014, "Anup Rubens"),
        ("Gopi Sundar Telugu", 2018, "Gopi Sundar"),
        ("Vivek Sagar Telugu", 2019, "Vivek Sagar"),
        ("Hesham Abdul Wahab Telugu", 2023, "Hesham Abdul Wahab"),
        ("Bheems Ceciroleo Telugu", 2023, "Bheems Ceciroleo"),
    ]

    harvested: List[Dict] = []
    session = requests.Session()

    for query_term, default_year, default_composer in search_queries:
        url = "https://itunes.apple.com/search"
        params = {
            "term": query_term,
            "country": "IN",
            "media": "music",
            "entity": "song",
            "limit": 120,
        }
        try:
            res = session.get(url, params=params, timeout=15)
            if res.status_code != 200:
                continue
            results = res.json().get("results", [])
            for idx, item in enumerate(results):
                raw_title = item.get("trackName", "")
                raw_movie = item.get("collectionName", "")
                artist_name = item.get("artistName", "")
                release_date = item.get("releaseDate", "")

                title = clean_title_or_movie(raw_title)
                movie = clean_title_or_movie(raw_movie)
                if not title or not movie or "karaoke" in title.lower():
                    continue

                # Determine Year & Composer (prefer Wikidata ground truth over remaster dates)
                movie_slug = slugify(movie)
                if movie_slug in wikidata_movies:
                    year, wd_composer = wikidata_movies[movie_slug]
                    composer, singers = extract_composer_and_singers(artist_name, wd_composer)
                else:
                    parsed_year = int(release_date[:4]) if release_date and release_date[:4].isdigit() else default_year
                    # If an old composer's album has a 2015+ digital remaster date, snap to their active era
                    if default_year < 1995 and parsed_year > 2005:
                        year = default_year
                    else:
                        year = max(1970, min(2026, parsed_year))
                    composer, singers = extract_composer_and_singers(artist_name, default_composer)

                decade = year_to_decade(year)
                # Rank-based popularity score (68 to 96)
                popularity = max(68, 96 - (idx // 4))

                harvested.append({
                    "title": title,
                    "movie": movie,
                    "year": year,
                    "decade": decade,
                    "composer": composer,
                    "singers": singers,
                    "mood": infer_mood(title),
                    "popularity": popularity,
                })
            print(f"      Fetched {len(results):3d} tracks for '{query_term}'")
            time.sleep(0.4)  # Polite rate limit for iTunes Search API
        except Exception as exc:
            print(f"      [Skip] {query_term}: {exc}")

    return harvested


def shard_and_export(all_tracks: List[Dict], output_dir: Path = OUTPUT_DIR) -> None:
    print("[3/3] Deduplicating, generating IDs, and writing decade JSON shards...")
    output_dir.mkdir(parents=True, exist_ok=True)

    shards: Dict[str, List[Dict]] = {d: [] for d in DECADES}
    seen_keys: Set[str] = set()
    movie_counters: Dict[str, int] = {}

    for track in all_tracks:
        dedup_key = f"{slugify(track['title'])}_{slugify(track['movie'])}"
        if dedup_key in seen_keys or len(slugify(track["title"])) < 3:
            continue
        seen_keys.add(dedup_key)

        decade = track["decade"]
        if decade not in shards:
            continue

        movie_key = f"{track['year']}_{slugify(track['movie'])}"
        movie_counters[movie_key] = movie_counters.get(movie_key, 0) + 1
        seq = movie_counters[movie_key]

        record = {
            "id": f"tel_{movie_key}_{seq:02d}",
            "title": track["title"],
            "movie": track["movie"],
            "year": track["year"],
            "decade": decade,
            "composer": track["composer"],
            "singers": track["singers"],
            "mood": track["mood"],
            "popularity": track["popularity"],
        }
        shards[decade].append(record)

    manifest = {
        "version": "2.0.0",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_songs": 0,
        "shards": {},
    }

    for decade, songs in shards.items():
        # Sort highest popularity first
        songs.sort(key=lambda x: (-x["popularity"], x["year"]))
        filename = f"telugu_{decade}.json"
        filepath = output_dir / filename

        payload = json.dumps(songs, ensure_ascii=False, indent=2)
        filepath.write_text(payload, encoding="utf-8")

        sha256_hash = hashlib.sha256(payload.encode("utf-8")).hexdigest()[:12]
        size_kb = round(len(payload.encode("utf-8")) / 1024, 1)

        manifest["total_songs"] += len(songs)
        manifest["shards"][decade] = {
            "file": filename,
            "count": len(songs),
            "size_kb": size_kb,
            "sha256_short": sha256_hash,
        }
        print(f"      [OK] Wrote {filepath} ({len(songs)} songs, {size_kb} KB)")

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nDone! Generated {manifest['total_songs']} unique Telugu songs across 6 shards in './{output_dir}/'.")


if __name__ == "__main__":
    wd_movies = fetch_wikidata_telugu_movies()
    itunes_tracks = harvest_itunes_telugu_songs(wd_movies)
    # Seed tracks go first so curated popularity scores take priority during deduplication
    combined = EVERGREEN_SEED + itunes_tracks
    shard_and_export(combined)
