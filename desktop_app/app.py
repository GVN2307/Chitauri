import os
import sys
import json
import time
import shutil
import urllib.parse
import threading
import subprocess
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import webview

# 1. Determine storage directories
USER_HOME = Path.home()
MUSIC_DIR = USER_HOME / "Music" / "ChitauriMusic"
MUSIC_DIR.mkdir(parents=True, exist_ok=True)

# 2. Enforce .nomedia sentinel for storage isolation
NOMEDIA_SENTINEL = MUSIC_DIR / ".nomedia"
if not NOMEDIA_SENTINEL.exists():
    try:
        NOMEDIA_SENTINEL.touch(exist_ok=True)
    except Exception as e:
        print(f"Warning: Could not create .nomedia: {e}")

CATALOG_FILE = MUSIC_DIR / "tracks_catalog.json"
if not CATALOG_FILE.exists():
    with open(CATALOG_FILE, "w", encoding="utf-8") as f:
        json.dump([], f)

# 3. Locate yt-dlp & ffmpeg
def find_binary(name):
    # Check bundled PyInstaller temporary folder first
    if hasattr(sys, "_MEIPASS"):
        bundled = Path(sys._MEIPASS) / f"{name}.exe"
        if bundled.exists():
            return str(bundled)

    # Check PATH
    found = shutil.which(name)
    if found:
        return found

    # Check common WinGet install locations
    winget_paths = list(Path.home().glob(f"AppData/Local/Microsoft/WinGet/Packages/*/{name}.exe")) + \
                   list(Path.home().glob(f"AppData/Local/Microsoft/WinGet/Packages/*/*/{name}.exe")) + \
                   list(Path.home().glob(f"AppData/Local/Microsoft/WinGet/Packages/*/*/*/{name}.exe"))
    if winget_paths:
        return str(winget_paths[0])

    return name

YTDLP_BIN = find_binary("yt-dlp")
FFMPEG_BIN = find_binary("ffmpeg")

# 4. Range-supporting HTTP Server for HTML5 Audio Streaming
class ChitauriHTTPHandler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        # Serve /stream/<filename> from MUSIC_DIR
        parsed = urllib.parse.urlparse(path)
        clean_path = urllib.parse.unquote(parsed.path)

        if clean_path.startswith("/stream/"):
            rel_name = clean_path[len("/stream/"):]
            return str(MUSIC_DIR / rel_name)

        # Serve frontend files from directory of index.html
        base_dir = Path(__file__).parent.resolve()
        if hasattr(sys, "_MEIPASS"):
            base_dir = Path(sys._MEIPASS).resolve()

        if clean_path in ("/", "/index.html"):
            return str(base_dir / "index.html")

        return str(base_dir / clean_path.lstrip("/"))

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Range, Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def log_message(self, format, *args):
        # Suppress verbose server log output
        pass

def start_http_server():
    server = ThreadingHTTPServer(("127.0.0.1", 0), ChitauriHTTPHandler)
    port = server.server_port
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return f"http://127.0.0.1:{port}"

# 5. Core JS API Bridge
class ChitauriAPI:
    def __init__(self, window, server_url):
        self.window = window
        self.server_url = server_url

    def search(self, query):
        trimmed = query.strip()
        if not trimmed:
            return []

        cmd = [
            YTDLP_BIN,
            f"ytsearch12:{trimmed}",
            "--dump-json",
            "--flat-playlist",
            "--no-warnings"
        ]

        try:
            startupinfo = None
            if os.name == "nt":
                startupinfo = subprocess.STARTUPINFO()
                startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                startupinfo=startupinfo
            )
            stdout, _ = process.communicate(timeout=25)

            results = []
            for line in stdout.strip().split("\n"):
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    v_id = data.get("id") or ""
                    title = data.get("title") or "Unknown Title"
                    channel = data.get("channel") or data.get("uploader") or "Artist"
                    duration = data.get("duration") or 180
                    duration_str = data.get("duration_string") or f"{int(duration)//60}:{int(duration)%60:02d}"

                    # Pick best thumbnail
                    thumbs = data.get("thumbnails") or []
                    thumbnail_url = thumbs[-1].get("url") if thumbs else f"https://i.ytimg.com/vi/{v_id}/hqdefault.jpg"

                    results.append({
                        "id": v_id,
                        "title": title,
                        "channel": channel,
                        "duration": duration,
                        "duration_string": duration_str,
                        "thumbnail": thumbnail_url
                    })
                except Exception:
                    continue

            return results
        except Exception as e:
            print(f"Search exception: {e}")
            return []

    def download(self, video_id, title, channel, thumbnail_url, is_duplicate=False):
        thread = threading.Thread(
            target=self._download_worker,
            args=(video_id, title, channel, thumbnail_url, is_duplicate),
            daemon=True
        )
        thread.start()
        return {"status": "started"}

    def _download_worker(self, video_id, title, channel, thumbnail_url, is_duplicate):
        # Sanitize filename
        safe_title = "".join(c for c in title if c not in '<>:"/\\|?*').strip()
        if not safe_title:
            safe_title = f"Chitauri_{video_id}"

        if is_duplicate:
            # Find next free duplicate index
            idx = 2
            while (MUSIC_DIR / f"{safe_title} ({idx}).mp3").exists():
                idx += 1
            out_filename = f"{safe_title} ({idx}).mp3"
        else:
            out_filename = f"{safe_title}.mp3"

        out_template = str(MUSIC_DIR / (out_filename[:-4] + ".%(ext)s"))

        cmd = [
            YTDLP_BIN,
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "--newline",
            "--no-warnings",
            "--embed-thumbnail",
            "--add-metadata",
            "-o", out_template,
            f"https://www.youtube.com/watch?v={video_id}"
        ]

        if FFMPEG_BIN:
            cmd.extend(["--ffmpeg-location", FFMPEG_BIN])

        startupinfo = None
        if os.name == "nt":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

        try:
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                startupinfo=startupinfo
            )

            # Read progress line by line
            percent = 10
            for line in process.stdout:
                line = line.strip()
                if "[download]" in line and "%" in line:
                    try:
                        parts = line.split("%")[0].split()
                        val = float(parts[-1])
                        # Map yt-dlp download percentage 0-100 to 10-85% overall
                        p = 10.0 + (val * 0.75)
                        if self.window:
                            self.window.evaluate_js(f"window.onDownloadProgress('{video_id}', {p})")
                    except Exception:
                        pass
                elif "[ExtractAudio]" in line or "[ffmpeg]" in line:
                    if self.window:
                        self.window.evaluate_js(f"window.onDownloadProgress('{video_id}', 90)")

            process.wait()

            # Verify output file
            final_path = MUSIC_DIR / out_filename
            if not final_path.exists():
                # Check if file has m4a, opus or other extension
                stem = out_filename[:-4]
                matching = list(MUSIC_DIR.glob(f"{stem}.*"))
                if matching and not matching[0].name.endswith(".nomedia"):
                    final_path = matching[0]
                    out_filename = final_path.name

            # Add to tracks_catalog.json
            track_record = {
                "id": video_id,
                "title": safe_title,
                "artist": channel,
                "duration": 180,
                "filename": out_filename,
                "thumbnail": thumbnail_url,
                "timestamp": int(time.time()),
                "stream_url": f"{self.server_url}/stream/{urllib.parse.quote(out_filename)}"
            }

            self._save_track_to_catalog(track_record)

            if self.window:
                self.window.evaluate_js(f"window.onDownloadProgress('{video_id}', 100)")
                self.window.evaluate_js(f"window.onDownloadComplete({json.dumps(track_record)})")

        except Exception as e:
            print(f"Download exception: {e}")

    def _save_track_to_catalog(self, track_record):
        try:
            with open(CATALOG_FILE, "r", encoding="utf-8") as f:
                catalog = json.load(f)
        except Exception:
            catalog = []

        # Remove duplicate entry if present
        catalog = [t for t in catalog if t.get("filename") != track_record.get("filename")]
        catalog.append(track_record)

        with open(CATALOG_FILE, "w", encoding="utf-8") as f:
            json.dump(catalog, f, indent=2)

    def get_library(self):
        try:
            with open(CATALOG_FILE, "r", encoding="utf-8") as f:
                catalog = json.load(f)
        except Exception:
            catalog = []

        # Refresh stream_url with current active server port
        for t in catalog:
            fn = t.get("filename") or ""
            t["stream_url"] = f"{self.server_url}/stream/{urllib.parse.quote(fn)}"

        return catalog

    def delete_track(self, track_id):
        try:
            with open(CATALOG_FILE, "r", encoding="utf-8") as f:
                catalog = json.load(f)
        except Exception:
            catalog = []

        new_catalog = []
        for t in catalog:
            if t.get("id") == track_id:
                # Remove physical file
                fn = t.get("filename")
                if fn:
                    fp = MUSIC_DIR / fn
                    if fp.exists():
                        try:
                            fp.unlink()
                        except Exception as e:
                            print(f"Could not delete physical file: {e}")
            else:
                new_catalog.append(t)

        with open(CATALOG_FILE, "w", encoding="utf-8") as f:
            json.dump(new_catalog, f, indent=2)

        return self.get_library()

    def get_stats(self):
        library = self.get_library()
        total_bytes = 0
        for item in MUSIC_DIR.glob("*"):
            if item.is_file() and not item.name.startswith("."):
                total_bytes += item.stat().st_size

        return {
            "total_tracks": len(library),
            "total_size_mb": round(total_bytes / (1024 * 1024), 2),
            "storage_path": str(MUSIC_DIR)
        }

    def get_audio_url(self, filename):
        return f"{self.server_url}/stream/{urllib.parse.quote(filename)}"

    def open_storage_folder(self):
        if os.name == "nt":
            os.startfile(str(MUSIC_DIR))
        return True


def main():
    server_url = start_http_server()
    api = ChitauriAPI(None, server_url)

    window = webview.create_window(
        title="Chitauri Audio Suite",
        url=f"{server_url}/index.html",
        js_api=api,
        width=440,
        height=880,
        min_size=(380, 600),
        resizable=True,
        background_color="#131315"
    )
    api.window = window

    webview.start(debug=False)

if __name__ == "__main__":
    main()
