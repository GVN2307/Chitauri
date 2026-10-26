import os
import sys
import json
import time
import shutil
import base64
import urllib.parse
import threading
import subprocess
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import webview

# Optional direct yt_dlp import
try:
    import yt_dlp
    HAS_YTDLP_MODULE = True
except ImportError:
    HAS_YTDLP_MODULE = False

# 1. Directories and Storage Isolation
USER_HOME = Path.home()
MUSIC_DIR = USER_HOME / "Music" / "ChitauriMusic"
MUSIC_DIR.mkdir(parents=True, exist_ok=True)

# Sentinel for storage isolation
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

# 2. Locate yt-dlp & ffmpeg binaries for fallback / fast execution
def find_binary(name):
    if hasattr(sys, "_MEIPASS"):
        bundled = Path(sys._MEIPASS) / f"{name}.exe"
        if bundled.exists():
            return str(bundled)

    found = shutil.which(name)
    if found:
        return found

    winget_paths = list(Path.home().glob(f"AppData/Local/Microsoft/WinGet/Packages/*/{name}.exe")) + \
                   list(Path.home().glob(f"AppData/Local/Microsoft/WinGet/Packages/*/*/{name}.exe")) + \
                   list(Path.home().glob(f"AppData/Local/Microsoft/WinGet/Packages/*/*/*/{name}.exe"))
    if winget_paths:
        return str(winget_paths[0])

    return name

YTDLP_BIN = find_binary("yt-dlp")
FFMPEG_BIN = find_binary("ffmpeg")

# Global Download Manager State
ACTIVE_DOWNLOADS = {}
DOWNLOAD_LOCK = threading.Lock()
ACTIVE_SERVER_PORT = 0

def format_duration(seconds):
    try:
        sec = int(seconds)
        m = sec // 60
        s = sec % 60
        return f"{m}:{s:02d}"
    except Exception:
        return "3:30"

# 3. Custom REST & Range-supporting HTTP Server
class ChitauriDesktopServer(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Range, Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        # REST API: Search
        if path == "/api/search":
            q = query.get("q", [""])[0].strip()
            results = perform_search(q)
            self._send_json(results)
            return

        # REST API: Stream URL (Live YouTube Audio Stream Resolver)
        if path == "/api/stream_url":
            video_id = query.get("id", [""])[0].strip()
            if not video_id:
                self._send_json({"error": "Missing video id"}, status=400)
                return
            stream_info = resolve_live_stream_url(video_id)
            self._send_json(stream_info)
            return

        # REST API: Library
        if path == "/api/library":
            lib = get_library_catalog()
            self._send_json(lib)
            return

        # REST API: Active Downloads
        if path == "/api/downloads/status":
            with DOWNLOAD_LOCK:
                items = list(ACTIVE_DOWNLOADS.values())
            self._send_json({"downloads": items})
            return

        # REST API: Storage Stats
        if path == "/api/stats":
            stats = compute_storage_stats()
            self._send_json(stats)
            return

        # Stream audio from MUSIC_DIR
        if path.startswith("/stream/"):
            rel_name = urllib.parse.unquote(path[len("/stream/"):])
            file_path = MUSIC_DIR / rel_name
            if not file_path.exists() or not file_path.is_file():
                self.send_error(404, "Audio file not found")
                return
            self._serve_audio_file(file_path)
            return

        # Serve static frontend files
        base_dir = Path(__file__).parent.resolve()
        if hasattr(sys, "_MEIPASS"):
            base_dir = Path(sys._MEIPASS).resolve()

        if path in ("/", "/index.html"):
            index_path = base_dir / "index.html"
            if not index_path.exists():
                index_path = base_dir / "desktop_app" / "index.html"
            if index_path.exists():
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                data = index_path.read_bytes()
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return

        if path == "/logo.png":
            logo_path = base_dir / "logo.png"
            if not logo_path.exists():
                logo_path = base_dir / "desktop_app" / "logo.png"
            if not logo_path.exists():
                logo_path = Path(__file__).resolve().parent.parent / "assets" / "logo.png"
            if logo_path.exists():
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                data = logo_path.read_bytes()
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return

        if path in ("/logo.ico", "/favicon.ico"):
            ico_path = base_dir / "logo.ico"
            if not ico_path.exists():
                ico_path = base_dir / "desktop_app" / "logo.ico"
            if not ico_path.exists():
                ico_path = Path(__file__).resolve().parent.parent / "assets" / "logo.ico"
            if ico_path.exists():
                self.send_response(200)
                self.send_header("Content-Type", "image/x-icon")
                data = ico_path.read_bytes()
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return

        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length) if content_length > 0 else b"{}"
        try:
            payload = json.loads(post_data.decode("utf-8"))
        except Exception:
            payload = {}

        if path == "/api/download":
            video_id = payload.get("id", "")
            title = payload.get("title", "")
            channel = payload.get("channel", "")
            thumbnail = payload.get("thumbnail", "")
            is_duplicate = payload.get("is_duplicate", False)

            if not video_id:
                self._send_json({"error": "Missing video id"}, status=400)
                return

            trigger_download(video_id, title, channel, thumbnail, is_duplicate)
            self._send_json({"status": "started", "id": video_id})
            return

        if path == "/api/delete":
            track_id = payload.get("id", "")
            updated_lib = delete_track_record(track_id)
            self._send_json(updated_lib)
            return

        if path == "/api/open_folder":
            if os.name == "nt":
                os.startfile(str(MUSIC_DIR))
            self._send_json({"status": "opened", "path": str(MUSIC_DIR)})
            return

        if path == "/api/install_shortcuts":
            ensure_windows_shortcuts()
            self._send_json({"status": "installed"})
            return

        if path == "/api/save_screenshot":
            name = payload.get("name", "screenshot.png")
            data_str = payload.get("data", "")
            if "," in data_str:
                data_str = data_str.split(",", 1)[1]
            try:
                img_bytes = base64.b64decode(data_str)
                # Save to workspace root directory
                target_path = Path(__file__).resolve().parent.parent / name
                target_path.write_bytes(img_bytes)
                print(f"Screenshot saved successfully: {target_path} ({len(img_bytes)} bytes)")
                self._send_json({"status": "saved", "path": str(target_path)})
            except Exception as e:
                print(f"Failed to save screenshot: {e}")
                self._send_json({"error": str(e)}, status=500)
            return

        self.send_error(404, "Not Found")

    def _send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_audio_file(self, file_path):
        size = file_path.stat().st_size
        range_header = self.headers.get("Range")

        ext = file_path.suffix.lower()
        content_type = "audio/mpeg" if ext == ".mp3" else ("audio/mp4" if ext == ".m4a" else "audio/ogg")

        if not range_header:
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(size))
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            with open(file_path, "rb") as f:
                shutil.copyfileobj(f, self.wfile)
            return

        try:
            parts = range_header.strip().replace("bytes=", "").split("-")
            start = int(parts[0]) if parts[0] else 0
            end = int(parts[1]) if parts[1] else size - 1
            if end >= size:
                end = size - 1
            length = end - start + 1

            self.send_response(206)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.send_header("Content-Length", str(length))
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()

            with open(file_path, "rb") as f:
                f.seek(start)
                remaining = length
                chunk_size = 64 * 1024
                while remaining > 0:
                    read_len = min(chunk_size, remaining)
                    chunk = f.read(read_len)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except Exception:
            pass

    def translate_path(self, path):
        # Override translate_path to serve frontend files
        base_dir = Path(__file__).parent.resolve()
        if hasattr(sys, "_MEIPASS"):
            base_dir = Path(sys._MEIPASS).resolve()
        clean_path = urllib.parse.unquote(urllib.parse.urlparse(path).path).lstrip("/")
        target = base_dir / clean_path
        if not target.exists() and (base_dir / "desktop_app" / clean_path).exists():
            return str(base_dir / "desktop_app" / clean_path)
        return str(target)

    def log_message(self, format, *args):
        # Silence verbose request logs
        pass


# 4. Search & Stream Resolution (High resilience: yt_dlp python module or yt-dlp CLI)
def resolve_live_stream_url(video_id):
    # Check if file exists in offline vault
    catalog = get_library_catalog()
    for item in catalog:
        if item.get("id") == video_id and item.get("filename"):
            fn = item["filename"]
            fp = MUSIC_DIR / fn
            if fp.exists():
                return {
                    "url": f"http://127.0.0.1:{ACTIVE_SERVER_PORT}/stream/{urllib.parse.quote(fn)}",
                    "is_local": True,
                    "title": item.get("title", ""),
                    "artist": item.get("artist", ""),
                    "thumbnail": item.get("thumbnail", "")
                }

    # Extract direct audio stream URL from YouTube
    if HAS_YTDLP_MODULE:
        try:
            ydl_opts = {
                "format": "bestaudio/best",
                "quiet": True,
                "no_warnings": True,
                "skip_download": True
            }
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
                stream_url = info.get("url")
                if stream_url:
                    return {
                        "url": stream_url,
                        "is_local": False,
                        "title": info.get("title", ""),
                        "artist": info.get("channel") or info.get("uploader") or "Artist",
                        "thumbnail": info.get("thumbnail") or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
                    }
        except Exception as e:
            print(f"yt_dlp stream resolution error: {e}")

    try:
        cmd = [YTDLP_BIN, "-g", "-f", "bestaudio/best", f"https://www.youtube.com/watch?v={video_id}"]
        startupinfo = None
        if os.name == "nt":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, startupinfo=startupinfo)
        stdout, _ = proc.communicate(timeout=15)
        raw_url = stdout.strip().split("\n")[0].strip()
        if raw_url.startswith("http"):
            return {
                "url": raw_url,
                "is_local": False
            }
    except Exception as e:
        print(f"CLI stream resolution error: {e}")

    return {"error": "Could not resolve stream URL"}


def perform_search(query):
    clean = query.strip()
    if not clean or clean.lower() in ("home", "trending", "yt home"):
        target_query = "ytsearch16:Trending Music Charts"
        is_direct_url = False
    elif clean.startswith("http://") or clean.startswith("https://") or "youtube.com/" in clean or "youtu.be/" in clean:
        target_query = clean
        is_direct_url = True
    else:
        target_query = f"ytsearch16:{clean}"
        is_direct_url = False

    # Priority 1: Direct yt_dlp Python module
    if HAS_YTDLP_MODULE:
        try:
            ydl_opts = {
                "quiet": True,
                "no_warnings": True,
                "extract_flat": True,
                "skip_download": True
            }
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                res = ydl.extract_info(target_query, download=False)
                if not res:
                    entries = []
                elif "entries" in res:
                    entries = res.get("entries") or []
                else:
                    entries = [res]

                results = []
                for item in entries:
                    if not item:
                        continue
                    v_id = item.get("id") or ""
                    title = item.get("title") or "Unknown Track"
                    channel = item.get("channel") or item.get("uploader") or "Artist"
                    duration = item.get("duration") or 180
                    duration_str = item.get("duration_string") or format_duration(duration)

                    thumbs = item.get("thumbnails") or []
                    thumb_url = thumbs[-1].get("url") if thumbs else f"https://i.ytimg.com/vi/{v_id}/hqdefault.jpg"

                    results.append({
                        "id": v_id,
                        "title": title,
                        "channel": channel,
                        "duration": duration,
                        "duration_string": duration_str,
                        "thumbnail": thumb_url
                    })
                if results:
                    return results
        except Exception as e:
            print(f"yt_dlp module search error: {e}")

    # Priority 2: yt-dlp CLI fallback
    try:
        cli_target = target_query if is_direct_url else target_query
        cmd = [
            YTDLP_BIN,
            cli_target,
            "--dump-json",
            "--flat-playlist",
            "--no-warnings"
        ]
        startupinfo = None
        if os.name == "nt":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            startupinfo=startupinfo
        )
        stdout, _ = proc.communicate(timeout=25)
        results = []
        for line in stdout.strip().split("\n"):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                v_id = data.get("id") or ""
                title = data.get("title") or "Unknown Track"
                channel = data.get("channel") or data.get("uploader") or "Artist"
                duration = data.get("duration") or 180
                duration_str = data.get("duration_string") or format_duration(duration)

                thumbs = data.get("thumbnails") or []
                thumb_url = thumbs[-1].get("url") if thumbs else f"https://i.ytimg.com/vi/{v_id}/hqdefault.jpg"

                results.append({
                    "id": v_id,
                    "title": title,
                    "channel": channel,
                    "duration": duration,
                    "duration_string": duration_str,
                    "thumbnail": thumb_url
                })
            except Exception:
                continue
        return results
    except Exception as e:
        print(f"CLI search exception: {e}")
        return []


# 5. Background Downloader
def trigger_download(video_id, title, channel, thumbnail, is_duplicate=False):
    t = threading.Thread(
        target=_download_worker,
        args=(video_id, title, channel, thumbnail, is_duplicate),
        daemon=True
    )
    t.start()

def _download_worker(video_id, title, channel, thumbnail, is_duplicate):
    safe_title = "".join(c for c in title if c not in '<>:"/\\|?*').strip()
    if not safe_title:
        safe_title = f"Chitauri_{video_id}"

    if is_duplicate:
        idx = 2
        while (MUSIC_DIR / f"{safe_title} ({idx}).mp3").exists():
            idx += 1
        out_filename = f"{safe_title} ({idx}).mp3"
    else:
        out_filename = f"{safe_title}.mp3"

    with DOWNLOAD_LOCK:
        ACTIVE_DOWNLOADS[video_id] = {
            "id": video_id,
            "title": safe_title,
            "artist": channel,
            "thumbnail": thumbnail,
            "percent": 5,
            "status": "Starting download...",
            "speed": "--"
        }

    out_template = str(MUSIC_DIR / (out_filename[:-4] + ".%(ext)s"))

    # Download using yt-dlp CLI for maximum reliability with ffmpeg conversion
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

    if FFMPEG_BIN and Path(FFMPEG_BIN).exists():
        cmd.extend(["--ffmpeg-location", FFMPEG_BIN])

    startupinfo = None
    if os.name == "nt":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            startupinfo=startupinfo
        )

        for line in proc.stdout:
            line = line.strip()
            if "[download]" in line and "%" in line:
                try:
                    parts = line.split("%")[0].split()
                    val = float(parts[-1])
                    p = min(90.0, 10.0 + (val * 0.75))
                    with DOWNLOAD_LOCK:
                        if video_id in ACTIVE_DOWNLOADS:
                            ACTIVE_DOWNLOADS[video_id]["percent"] = round(p, 1)
                            ACTIVE_DOWNLOADS[video_id]["status"] = f"Downloading {round(val)}%"
                            if "at" in line:
                                speed_part = line.split("at")[-1].split("ETA")[0].strip()
                                ACTIVE_DOWNLOADS[video_id]["speed"] = speed_part
                except Exception:
                    pass
            elif "[ExtractAudio]" in line or "[ffmpeg]" in line:
                with DOWNLOAD_LOCK:
                    if video_id in ACTIVE_DOWNLOADS:
                        ACTIVE_DOWNLOADS[video_id]["percent"] = 92
                        ACTIVE_DOWNLOADS[video_id]["status"] = "Converting 320kbps MP3..."

        proc.wait()

        # Check target file
        final_file = MUSIC_DIR / out_filename
        if not final_file.exists():
            stem = out_filename[:-4]
            candidates = list(MUSIC_DIR.glob(f"{stem}.*"))
            for c in candidates:
                if not c.name.endswith(".nomedia") and not c.name.endswith(".json"):
                    final_file = c
                    out_filename = c.name
                    break

        file_size_mb = 0
        if final_file.exists():
            file_size_mb = round(final_file.stat().st_size / (1024 * 1024), 2)

        # Catalog record
        record = {
            "id": video_id,
            "title": safe_title,
            "artist": channel,
            "duration": 180,
            "duration_string": "3:00",
            "filename": out_filename,
            "filesize_mb": file_size_mb,
            "thumbnail": thumbnail,
            "timestamp": int(time.time()),
            "stream_url": f"http://127.0.0.1:{ACTIVE_SERVER_PORT}/stream/{urllib.parse.quote(out_filename)}"
        }

        save_to_catalog(record)

        with DOWNLOAD_LOCK:
            if video_id in ACTIVE_DOWNLOADS:
                ACTIVE_DOWNLOADS[video_id]["percent"] = 100
                ACTIVE_DOWNLOADS[video_id]["status"] = "Completed"
                ACTIVE_DOWNLOADS[video_id]["speed"] = "Done"

        # Keep completed status for 10 seconds, then clean up
        def cleanup():
            time.sleep(12)
            with DOWNLOAD_LOCK:
                ACTIVE_DOWNLOADS.pop(video_id, None)

        threading.Thread(target=cleanup, daemon=True).start()

    except Exception as e:
        print(f"Download worker exception: {e}")
        with DOWNLOAD_LOCK:
            if video_id in ACTIVE_DOWNLOADS:
                ACTIVE_DOWNLOADS[video_id]["status"] = f"Failed: {e}"
                ACTIVE_DOWNLOADS[video_id]["percent"] = 0


# 6. Library Management & Synchronization
def save_to_catalog(record):
    try:
        with open(CATALOG_FILE, "r", encoding="utf-8") as f:
            catalog = json.load(f)
    except Exception:
        catalog = []

    # Deduplicate by filename
    catalog = [t for t in catalog if t.get("filename") != record.get("filename")]
    catalog.insert(0, record)

    with open(CATALOG_FILE, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2)

def get_library_catalog():
    try:
        with open(CATALOG_FILE, "r", encoding="utf-8") as f:
            catalog = json.load(f)
    except Exception:
        catalog = []

    # Reconcile disk files
    active_files = {}
    for p in MUSIC_DIR.glob("*"):
        if p.is_file() and not p.name.startswith("."):
            active_files[p.name] = p

    # Remove non-existent entries
    valid_catalog = []
    seen_files = set()
    for item in catalog:
        fn = item.get("filename")
        if fn in active_files:
            file_obj = active_files[fn]
            item["filesize_mb"] = round(file_obj.stat().st_size / (1024 * 1024), 2)
            item["stream_url"] = f"http://127.0.0.1:{ACTIVE_SERVER_PORT}/stream/{urllib.parse.quote(fn)}"
            valid_catalog.append(item)
            seen_files.add(fn)

    # Add any loose audio files not in catalog
    for fn, file_obj in active_files.items():
        if fn not in seen_files and fn != "tracks_catalog.json":
            stem = file_obj.stem
            size_mb = round(file_obj.stat().st_size / (1024 * 1024), 2)
            new_item = {
                "id": f"local_{int(time.time())}_{fn[:8]}",
                "title": stem,
                "artist": "Local Offline",
                "duration": 180,
                "duration_string": "3:00",
                "filename": fn,
                "filesize_mb": size_mb,
                "thumbnail": "",
                "timestamp": int(file_obj.stat().st_mtime),
                "stream_url": f"http://127.0.0.1:{ACTIVE_SERVER_PORT}/stream/{urllib.parse.quote(fn)}"
            }
            valid_catalog.append(new_item)

    # Save reconciled catalog
    with open(CATALOG_FILE, "w", encoding="utf-8") as f:
        json.dump(valid_catalog, f, indent=2)

    return valid_catalog

def delete_track_record(track_id):
    try:
        with open(CATALOG_FILE, "r", encoding="utf-8") as f:
            catalog = json.load(f)
    except Exception:
        catalog = []

    remaining = []
    for item in catalog:
        if item.get("id") == track_id:
            fn = item.get("filename")
            if fn:
                p = MUSIC_DIR / fn
                if p.exists():
                    try:
                        p.unlink()
                    except Exception as e:
                        print(f"Could not unlink {p}: {e}")
        else:
            remaining.append(item)

    with open(CATALOG_FILE, "w", encoding="utf-8") as f:
        json.dump(remaining, f, indent=2)

    return get_library_catalog()

def compute_storage_stats():
    lib = get_library_catalog()
    total_bytes = 0
    for p in MUSIC_DIR.glob("*"):
        if p.is_file() and not p.name.startswith("."):
            total_bytes += p.stat().st_size

    return {
        "total_tracks": len(lib),
        "total_size_mb": round(total_bytes / (1024 * 1024), 2),
        "storage_path": str(MUSIC_DIR),
        "nomedia_active": NOMEDIA_SENTINEL.exists()
    }


# 7. Windows Laptop Application & Self-Installation Setup
def ensure_windows_shortcuts():
    if os.name != "nt":
        return

    exe_path = Path(sys.executable).resolve()
    if "python" in exe_path.name.lower():
        candidate = Path(__file__).resolve().parent.parent / "chitauri.exe"
        if candidate.exists():
            exe_path = candidate
        else:
            return

    # Standard per-user Windows application directory (standard for VS Code, Discord, Spotify)
    app_install_dir = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local"))) / "Programs" / "Chitauri"
    app_install_dir.mkdir(parents=True, exist_ok=True)
    target_exe = app_install_dir / "chitauri.exe"
    target_ico = app_install_dir / "logo.ico"

    # 1. Locate and persist the application icon to the permanent installation directory
    ico_source = None
    if hasattr(sys, "_MEIPASS"):
        for sub in [Path(sys._MEIPASS) / "logo.ico", Path(sys._MEIPASS) / "desktop_app" / "logo.ico"]:
            if sub.exists():
                ico_source = sub
                break

    if not ico_source:
        for sub in [exe_path.parent / "desktop_app" / "logo.ico", exe_path.parent / "assets" / "logo.ico"]:
            if sub.exists():
                ico_source = sub
                break

    if ico_source and ico_source.exists():
        try:
            if not target_ico.exists() or target_ico.stat().st_size != ico_source.stat().st_size:
                shutil.copy2(ico_source, target_ico)
        except Exception:
            pass

    # 2. Self-provision binary into Programs directory if running from outside (e.g. Downloads folder)
    final_exe = exe_path
    if exe_path.resolve() != target_exe.resolve():
        try:
            shutil.copy2(exe_path, target_exe)
            final_exe = target_exe
        except Exception:
            if target_exe.exists():
                final_exe = target_exe
            else:
                final_exe = exe_path

    # Determine icon location for shortcuts
    if target_ico.exists():
        icon_loc = str(target_ico)
    elif ico_source and ico_source.exists():
        icon_loc = str(ico_source)
    else:
        icon_loc = str(final_exe)

    desktop_lnk = Path.home() / "Desktop" / "Chitauri.lnk"
    start_dir = Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs"
    start_dir.mkdir(parents=True, exist_ok=True)
    start_lnk = start_dir / "Chitauri.lnk"

    ps_code = f"""
$ws = New-Object -ComObject WScript.Shell

$s1 = $ws.CreateShortcut('{desktop_lnk}')
$s1.TargetPath = '{final_exe}'
$s1.IconLocation = '{icon_loc},0'
$s1.Description = 'Chitauri Desktop Audio Suite'
$s1.WorkingDirectory = '{final_exe.parent}'
$s1.Save()

$s2 = $ws.CreateShortcut('{start_lnk}')
$s2.TargetPath = '{final_exe}'
$s2.IconLocation = '{icon_loc},0'
$s2.Description = 'Chitauri Desktop Audio Suite'
$s2.WorkingDirectory = '{final_exe.parent}'
$s2.Save()

try {{
    $rk = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\chitauri.exe'
    if (-not (Test-Path $rk)) {{ New-Item -Path $rk -Force | Out-Null }}
    Set-ItemProperty -Path $rk -Name '(Default)' -Value '{final_exe}'
    Set-ItemProperty -Path $rk -Name 'Path' -Value '{final_exe.parent}'
}} catch {{}}
"""
    try:
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_code],
            startupinfo=startupinfo,
            check=False,
            timeout=8
        )
    except Exception as e:
        print(f"Shortcut setup note: {e}")


# 8. Start HTTP Server
def start_server():
    global ACTIVE_SERVER_PORT
    server = ThreadingHTTPServer(("127.0.0.1", 0), ChitauriDesktopServer)
    ACTIVE_SERVER_PORT = server.server_port
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    return f"http://127.0.0.1:{ACTIVE_SERVER_PORT}"


# 9. Main Entrypoint
def main():
    if os.name == "nt":
        # 1. Set AppUserModelID so Windows taskbar groups and shows official icon
        try:
            import ctypes
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("com.chitauri.audio.desktop")
        except Exception:
            pass

        # 2. Automatically ensure desktop and start menu shortcuts exist
        try:
            ensure_windows_shortcuts()
        except Exception as e:
            print(f"Auto shortcut error: {e}")

    server_url = start_server()
    print(f"Chitauri Desktop Server running on {server_url}")

    # Launch Desktop window (1260x820 widescreen layout)
    window = webview.create_window(
        title="Chitauri Desktop Audio Suite",
        url=f"{server_url}/index.html",
        width=1260,
        height=820,
        min_size=(960, 620),
        resizable=True,
        background_color="#0c0d12"
    )

    webview.start(debug=False)

if __name__ == "__main__":
    main()
