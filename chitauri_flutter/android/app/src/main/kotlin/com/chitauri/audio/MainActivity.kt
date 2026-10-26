package com.chitauri.audio

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.session.MediaButtonReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.YoutubeDLResponse
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.ffmpeg.FFmpeg

class MainActivity: FlutterActivity() {
    private val CHANNEL_FX = "com.chitauri.audio/hardware_fx"
    private val CHANNEL_YTDLP = "com.chitauri.audio/ytdlp"
    private val CHANNEL_MEDIA = "com.chitauri.audio/media_session"

    private val NOTIFICATION_CHANNEL_ID = "chitauri_playback_channel"
    private val NOTIFICATION_ID = 1001

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null

    private var isYtDlpInitialized = false
    private var isYtDlpInitializing = false
    private var ytDlpChannel: MethodChannel? = null
    private var mediaChannel: MethodChannel? = null

    private var mediaSession: MediaSessionCompat? = null
    private var currentTitle: String = "Chitauri Audio"
    private var currentArtist: String = "Offline Player"
    private var isPlayingState: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        requestNotificationAndMediaPermissions()
        initAudioEffects()
        initYoutubeDLAudioEngine()
        initMediaSession(flutterEngine)

        // 1. Hardware FX Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_FX).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBandLevel" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val level = call.argument<Int>("level") ?: 0 // millibels (-1200 to +1200)
                    try {
                        if (equalizer != null && band < (equalizer?.numberOfBands ?: 0)) {
                            equalizer?.setBandLevel(band.toShort(), level.toShort())
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("EQ_ERROR", e.message, null)
                    }
                }
                "setBassBoost" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val strength = call.argument<Int>("strength") ?: 1000 // 0 to 1000
                    try {
                        bassBoost?.enabled = enabled
                        if (enabled && (bassBoost?.strengthSupported == true)) {
                            bassBoost?.setStrength(strength.toShort())
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BASS_ERROR", e.message, null)
                    }
                }
                "setVirtualizer" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val strength = call.argument<Int>("strength") ?: 1000 // 0 to 1000
                    try {
                        virtualizer?.enabled = enabled
                        if (enabled && (virtualizer?.strengthSupported == true)) {
                            virtualizer?.setStrength(strength.toShort())
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VIRT_ERROR", e.message, null)
                    }
                }
                "shareAudioFile" -> {
                    val filePath = call.argument<String>("path")
                    val title = call.argument<String>("title") ?: "Chitauri Audio"
                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            try {
                                val uri: Uri = FileProvider.getUriForFile(
                                    this,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                    type = "audio/*"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_SUBJECT, title)
                                    putExtra(Intent.EXTRA_TEXT, "$title - Shared via Chitauri Audio Suite")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                val chooser = Intent.createChooser(shareIntent, "Share Audio via")
                                startActivity(chooser)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("SHARE_ERROR", e.message, null)
                            }
                        } else {
                            result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                        }
                    } else {
                        result.error("INVALID_PATH", "Path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 2. YoutubeDL + FFmpeg Audio Engine Channel (160 kbps Fast & Compact ~3.5MB per song)
        ytDlpChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_YTDLP).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isReady" -> {
                        result.success(isYtDlpInitialized)
                    }
                    "getAudioDuration" -> {
                        val filePath = call.argument<String>("path")
                        if (filePath != null) {
                            var durationSecs = 0
                            try {
                                val retriever = android.media.MediaMetadataRetriever()
                                retriever.setDataSource(filePath)
                                val timeStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                                val ms = timeStr?.toLongOrNull() ?: 0L
                                if (ms > 0) {
                                    durationSecs = (ms / 1000).toInt()
                                }
                                retriever.release()
                            } catch (_: Exception) {}
                            result.success(durationSecs)
                        } else {
                            result.success(0)
                        }
                    }
                    "getYoutubeCookies" -> {
                        try {
                            val cookieManager = android.webkit.CookieManager.getInstance()
                            val cookies = cookieManager.getCookie("https://www.youtube.com")
                                ?: cookieManager.getCookie("https://m.youtube.com")
                                ?: ""
                            result.success(cookies)
                        } catch (e: Exception) {
                            result.success("")
                        }
                    }
                    "getPlaylistVideos" -> {
                        val playlistUrl = call.argument<String>("url")
                        if (playlistUrl.isNullOrEmpty()) {
                            result.error("INVALID_URL", "Playlist URL required", null)
                            return@setMethodCallHandler
                        }
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                if (!isYtDlpInitialized) {
                                    try {
                                        YoutubeDL.getInstance().init(applicationContext)
                                        FFmpeg.getInstance().init(applicationContext)
                                        isYtDlpInitialized = true
                                    } catch (_: Exception) {}
                                }
                                val userAgent = try {
                                    android.webkit.WebSettings.getDefaultUserAgent(applicationContext)
                                } catch (_: Exception) {
                                    "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UD1A.230803.041) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
                                }
                                val cookies = try {
                                    val cookieManager = android.webkit.CookieManager.getInstance()
                                    cookieManager.getCookie("https://www.youtube.com")
                                        ?: cookieManager.getCookie("https://m.youtube.com")
                                        ?: ""
                                } catch (_: Exception) {
                                    ""
                                }
                                var canonicalUrl = playlistUrl
                                val listIdMatch = Regex("[?&]list=([a-zA-Z0-9_-]+)").find(playlistUrl)
                                if (listIdMatch != null) {
                                    val listId = listIdMatch.groupValues[1]
                                    canonicalUrl = "https://www.youtube.com/playlist?list=$listId"
                                }
                                val request = YoutubeDLRequest(canonicalUrl).apply {
                                    addOption("--flat-playlist")
                                    addOption("--yes-playlist")
                                    addOption("-J")
                                    addOption("--no-check-certificates")
                                    addOption("--user-agent", userAgent)
                                    if (cookies.isNotEmpty()) {
                                        addOption("--add-header", "Cookie: $cookies")
                                    }
                                    addOption("--extractor-args", "youtube:player_client=android,web,tv")
                                }
                                val response = YoutubeDL.getInstance().execute(request)
                                val jsonOut = response.out
                                Handler(Looper.getMainLooper()).post {
                                    result.success(jsonOut)
                                }
                            } catch (e: Exception) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("PLAYLIST_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "startDownloadService" -> {
                        val title = call.argument<String>("title") ?: "Downloading Audio"
                        ChitauriDownloadService.notifyDownloadStarted(applicationContext, title)
                        result.success(true)
                    }
                    "updateDownloadProgress" -> {
                        val title = call.argument<String>("title") ?: "Downloading Audio"
                        val progress = call.argument<Int>("progress") ?: 0
                        ChitauriDownloadService.notifyDownloadProgress(applicationContext, title, progress)
                        result.success(true)
                    }
                    "stopDownloadService" -> {
                        ChitauriDownloadService.notifyDownloadEnded(applicationContext)
                        result.success(true)
                    }
                    "killProcess" -> {
                        val processId = call.argument<String>("processId")
                        if (!processId.isNullOrEmpty()) {
                            try {
                                YoutubeDL.getInstance().destroyProcessById(processId)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("KILL_ERROR", e.message, null)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "downloadMp3" -> {
                        val videoId = call.argument<String>("videoId")
                        val title = call.argument<String>("title")
                        val url = call.argument<String>("url") ?: "https://www.youtube.com/watch?v=$videoId"
                        val outputDir = call.argument<String>("outputDir")

                        if (videoId.isNullOrEmpty() || outputDir.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "videoId and outputDir required", null)
                            return@setMethodCallHandler
                        }

                        // Run asynchronously on background Coroutine thread - NEVER block UI thread
                        CoroutineScope(Dispatchers.IO).launch {
                            val stagingDir = File(applicationContext.cacheDir, "ytdlp_staging")
                            var currentSafeBase = "Song_$videoId"
                            val processId = call.argument<String>("processId") ?: "${videoId}_${System.currentTimeMillis()}"

                            try {
                                // Ensure engine initialized
                                if (!isYtDlpInitialized) {
                                    try {
                                        YoutubeDL.getInstance().init(applicationContext)
                                        FFmpeg.getInstance().init(applicationContext)
                                        isYtDlpInitialized = true
                                    } catch (e: Exception) {
                                        Log.w("ChitauriAudio", "YtDlp lazy init error: ${e.message}")
                                    }
                                }

                                val outDirFile = File(outputDir)
                                if (!outDirFile.exists()) {
                                    outDirFile.mkdirs()
                                }

                                if (!stagingDir.exists()) {
                                    stagingDir.mkdirs()
                                }

                                val rawTitle = if (!title.isNullOrBlank()) title else "Song"
                                val cleanTitle = rawTitle
                                    .replace(Regex("_${Regex.escape(videoId)}$"), "")
                                    .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                                    .replace(Regex("\\s+"), " ")
                                    .trim()
                                    .take(50)
                                val safeBase = "${cleanTitle}_$videoId"
                                currentSafeBase = safeBase

                                val convertToMp3 = call.argument<Boolean>("convertToMp3") ?: true

                                // Purge any existing partial/staged files for this track
                                try {
                                    stagingDir.listFiles { _, name -> name.contains(safeBase) || name.contains(videoId) || name.startsWith(processId) }?.forEach { it.delete() }
                                } catch (_: Exception) {}

                                // Deterministic staging using unique processId
                                val stagingTemplate = "${stagingDir.absolutePath}/${processId}.%(ext)s"

                                val userAgent = try {
                                    android.webkit.WebSettings.getDefaultUserAgent(applicationContext)
                                } catch (_: Exception) {
                                    "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UD1A.230803.041) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
                                }
                                val cookies = try {
                                    val cookieManager = android.webkit.CookieManager.getInstance()
                                    cookieManager.getCookie("https://www.youtube.com")
                                        ?: cookieManager.getCookie("https://m.youtube.com")
                                        ?: ""
                                } catch (_: Exception) {
                                    ""
                                }

                                // Hold WakeLock and post ongoing Android Foreground Notification
                                ChitauriDownloadService.notifyDownloadStarted(applicationContext, safeBase)

                                val request = YoutubeDLRequest(url).apply {
                                    addOption("--no-check-certificates")
                                    addOption("--force-overwrites")
                                    addOption("--no-continue")
                                    addOption("--no-part")
                                    addOption("--retries", "3")
                                    addOption("--fragment-retries", "3")
                                    addOption("--user-agent", userAgent)
                                    if (cookies.isNotEmpty()) {
                                        addOption("--add-header", "Cookie: $cookies")
                                    }
                                    addOption("--extractor-args", "youtube:player_client=android,web,tv")
                                    if (convertToMp3) {
                                        // FFmpeg MP3 Extraction at optimal 160 kbps (~3.5MB per song, lightning fast transcode)
                                        addOption("-f", "ba[ext=m4a]/ba[ext=webm]/ba/b")
                                        addOption("-x")
                                        addOption("--audio-format", "mp3")
                                        addOption("--audio-quality", "4")
                                    } else {
                                        // Pure direct AAC stream download (~3.2MB download)
                                        addOption("-f", "140/ba/b")
                                    }
                                    addOption("--no-playlist")
                                    addOption("--no-mtime")
                                    addOption("--no-warnings")
                                    addOption("--socket-timeout", "30")
                                    addOption("-o", stagingTemplate)
                                }

                                val mainHandler = Handler(Looper.getMainLooper())
                                var lastProgressTime = 0L

                                YoutubeDL.getInstance().execute(request, processId) { progress, etaInSeconds, line ->
                                    val now = System.currentTimeMillis()
                                    if (now - lastProgressTime > 150 || progress >= 100f) {
                                        lastProgressTime = now

                                        // Only show percentage e.g. "45%" without long verbose process names
                                        val normProgress = if (progress > 0) (progress / 100.0).coerceIn(0.05, 0.95) else 0.05
                                        val pctInt = (normProgress * 100).toInt()
                                        val pctText = "$pctInt%"

                                        ChitauriDownloadService.notifyDownloadProgress(applicationContext, safeBase, pctInt)

                                        mainHandler.post {
                                            ytDlpChannel?.invokeMethod("onProgress", mapOf(
                                                "videoId" to videoId,
                                                "progress" to normProgress,
                                                "statusText" to pctText,
                                                "eta" to etaInSeconds
                                            ))
                                        }
                                    }
                                }

                                // Locate completed file deterministically via processId prefix
                                var resultFile: File? = File(stagingDir, "${processId}.mp3")
                                if (resultFile?.exists() != true || resultFile.length() < 50000) {
                                    val m4aCandidate = File(stagingDir, "${processId}.m4a")
                                    if (m4aCandidate.exists() && m4aCandidate.length() >= 50000) {
                                        resultFile = m4aCandidate
                                    }
                                }
                                if (resultFile?.exists() != true || resultFile.length() < 50000) {
                                    val candidates = stagingDir.listFiles { _, name ->
                                        name.startsWith(processId) &&
                                        !name.endsWith(".part") &&
                                        !name.endsWith(".ytdl") &&
                                        !name.endsWith(".tmp")
                                    }
                                    if (!candidates.isNullOrEmpty()) {
                                        // Strongly prioritize true audio (.mp3, .m4a) over any video files
                                        candidates.sortByDescending { file ->
                                            val audioBonus = if (file.name.endsWith(".mp3") || file.name.endsWith(".m4a")) 1000000000L else 0L
                                            audioBonus + file.length()
                                        }
                                        resultFile = candidates.firstOrNull { it.length() >= 50000 }
                                    }
                                }

                                if (resultFile != null && resultFile.exists() && resultFile.length() >= 50000) {
                                    val finalExt = resultFile.extension.ifEmpty { if (convertToMp3) "mp3" else "m4a" }
                                    val destFile = File(outDirFile, "${safeBase}.$finalExt")

                                    // Extract true audio duration from file header using Android native OS
                                    var trackDurationSecs = 0
                                    try {
                                        val retriever = android.media.MediaMetadataRetriever()
                                        retriever.setDataSource(resultFile.absolutePath)
                                        val timeStr = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                                        val ms = timeStr?.toLongOrNull() ?: 0L
                                        if (ms > 0) {
                                            trackDurationSecs = (ms / 1000).toInt()
                                        }
                                        retriever.release()
                                    } catch (_: Exception) {}

                                    mainHandler.post {
                                        ytDlpChannel?.invokeMethod("onProgress", mapOf(
                                            "videoId" to videoId,
                                            "progress" to 1.0,
                                            "statusText" to "100%",
                                            "eta" to 0
                                        ))
                                    }

                                    // Atomically place into official music library
                                    resultFile.copyTo(destFile, overwrite = true)
                                    resultFile.delete()

                                    mainHandler.post {
                                        result.success(mapOf(
                                            "success" to true,
                                            "filePath" to destFile.absolutePath,
                                            "fileSize" to destFile.length(),
                                            "durationSecs" to trackDurationSecs
                                        ))
                                    }
                                } else {
                                    mainHandler.post {
                                        result.error("DOWNLOAD_FAILED", "Output file not found in staging", null)
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e("ChitauriAudio", "YtDlp download exception: ${e.message}", e)
                                try {
                                    val leftovers = stagingDir.listFiles { _, name -> name.contains(videoId) || name.contains(currentSafeBase) || name.startsWith(processId) }
                                    leftovers?.forEach { it.delete() }
                                } catch (_: Exception) {}

                                Handler(Looper.getMainLooper()).post {
                                    result.error("YTDLP_ERROR", e.message, null)
                                }
                            } finally {
                                ChitauriDownloadService.notifyDownloadEnded(applicationContext)
                                try {
                                    YoutubeDL.getInstance().destroyProcessById(processId)
                                } catch (_: Exception) {}
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // 3. Native MediaSession & Android Notification / Lockscreen / Dynamic Island Controller
    private fun initMediaSession(flutterEngine: FlutterEngine) {
        createNotificationChannel()

        mediaSession = MediaSessionCompat(this, "ChitauriAudioSuite").apply {
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    mediaChannel?.invokeMethod("onAction", "play")
                }
                override fun onPause() {
                    mediaChannel?.invokeMethod("onAction", "pause")
                }
                override fun onSkipToNext() {
                    mediaChannel?.invokeMethod("onAction", "next")
                }
                override fun onSkipToPrevious() {
                    mediaChannel?.invokeMethod("onAction", "previous")
                }
                override fun onSeekTo(pos: Long) {
                    mediaChannel?.invokeMethod("onActionSeek", pos)
                }
                override fun onStop() {
                    mediaChannel?.invokeMethod("onAction", "stop")
                    cancelMediaNotification()
                }
            })
            isActive = true
        }

        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_MEDIA).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "updatePlayback" -> {
                        val title = call.argument<String>("title") ?: "Chitauri Track"
                        val artist = call.argument<String>("artist") ?: "Music Artist"
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                        val positionMs = (call.argument<Int>("positionMs") ?: 0).toLong()
                        val durationMs = (call.argument<Int>("durationMs") ?: 228000).toLong()
                        val thumbUrl = call.argument<String>("thumbnailUrl")

                        currentTitle = title
                        currentArtist = artist
                        isPlayingState = isPlaying

                        updateNativeMediaState(title, artist, isPlaying, positionMs, durationMs, thumbUrl)
                        result.success(true)
                    }
                    "stop" -> {
                        cancelMediaNotification()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Chitauri Music Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Lockscreen, Control Center, Bluetooth & Dynamic Island playback controls"
                setShowBadge(false)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun updateNativeMediaState(
        title: String,
        artist: String,
        isPlaying: Boolean,
        positionMs: Long,
        durationMs: Long,
        thumbUrl: String?
    ) {
        val session = mediaSession ?: return

        // Resolve album art bitmap (from local disk file or remote)
        var bitmap = currentAlbumArt
        if (thumbUrl != null && thumbUrl != currentThumbUrl) {
            currentThumbUrl = thumbUrl
            try {
                val f = File(thumbUrl)
                if (f.exists()) {
                    currentAlbumArt = BitmapFactory.decodeFile(f.absolutePath)
                    bitmap = currentAlbumArt
                } else if (thumbUrl.startsWith("http")) {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val stream = URL(thumbUrl).openStream()
                            val loaded = BitmapFactory.decodeStream(stream)
                            if (loaded != null) {
                                currentAlbumArt = loaded
                                withContext(Dispatchers.Main) {
                                    updateNativeMediaState(title, artist, isPlaying, positionMs, durationMs, thumbUrl)
                                }
                            }
                        } catch (_: Exception) {}
                    }
                }
            } catch (_: Exception) {}
        }

        // 1. Update MediaMetadata for Bluetooth AVRCP & System Player
        val metadataBuilder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, "Chitauri Music")
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)

        if (bitmap != null) {
            metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
            metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, bitmap)
        }

        session.setMetadata(metadataBuilder.build())

        // 2. Update PlaybackStateCompat
        val state = if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val actions = PlaybackStateCompat.ACTION_PLAY or
                      PlaybackStateCompat.ACTION_PAUSE or
                      PlaybackStateCompat.ACTION_PLAY_PAUSE or
                      PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                      PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                      PlaybackStateCompat.ACTION_SEEK_TO or
                      PlaybackStateCompat.ACTION_STOP

        val playbackState = PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(state, positionMs, if (isPlaying) 1.0f else 0.0f)
            .build()

        session.setPlaybackState(playbackState)

        // 3. Post Foreground Notification (Lockscren, Notification Shade, Android 16 Live Updates)
        showMediaNotification(title, artist, isPlaying, bitmap)
    }

    private var currentAlbumArt: Bitmap? = null
    private var currentThumbUrl: String? = null

    private fun requestNotificationAndMediaPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permissionsToRequest = mutableListOf<String>()
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.POST_NOTIFICATIONS)
            }
            if (checkSelfPermission(Manifest.permission.READ_MEDIA_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.READ_MEDIA_AUDIO)
            }
            if (permissionsToRequest.isNotEmpty()) {
                requestPermissions(permissionsToRequest.toTypedArray(), 1002)
            }
        }
    }

    private fun showMediaNotification(title: String, artist: String, isPlaying: Boolean, largeIcon: Bitmap? = null) {
        val session = mediaSession ?: return

        val appIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this, 0, appIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val prevIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        val playPauseAction = if (isPlaying) PlaybackStateCompat.ACTION_PAUSE else PlaybackStateCompat.ACTION_PLAY
        val playPauseIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, playPauseAction)
        val nextIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)

        val notificationBuilder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText("Chitauri")
            .setContentIntent(contentPendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true) // Pinned persistent widget: stays on lockscreen & notification panel until stopped
            .addAction(android.R.drawable.ic_media_previous, "Previous", prevIntent)
            .addAction(if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, if (isPlaying) "Pause" else "Play", playPauseIntent)
            .addAction(android.R.drawable.ic_media_next, "Next", nextIntent)
            .setStyle(
                MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        val art = largeIcon ?: currentAlbumArt
        if (art != null) {
            notificationBuilder.setLargeIcon(art)
        }

        val notification = notificationBuilder.build().apply {
            flags = flags or Notification.FLAG_ONGOING_EVENT or Notification.FLAG_NO_CLEAR
        }

        // Pinned persistent widget via Foreground Service
        ChitauriPlaybackService.startOrUpdate(this, notification)
    }

    private fun cancelMediaNotification() {
        ChitauriPlaybackService.stop(this)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
        mediaSession?.setPlaybackState(
            PlaybackStateCompat.Builder().setState(PlaybackStateCompat.STATE_STOPPED, 0, 0f).build()
        )
    }

    private fun initYoutubeDLAudioEngine() {
        if (isYtDlpInitialized || isYtDlpInitializing) return
        isYtDlpInitializing = true
        CoroutineScope(Dispatchers.IO).launch {
            try {
                YoutubeDL.getInstance().init(applicationContext)
                FFmpeg.getInstance().init(applicationContext)
                isYtDlpInitialized = true
                Log.i("ChitauriAudio", "YoutubeDL + Python + FFmpeg successfully initialized")
            } catch (e: Exception) {
                Log.e("ChitauriAudio", "Failed to init YoutubeDL: ${e.message}", e)
            } finally {
                isYtDlpInitializing = false
            }
        }
    }

    private fun initAudioEffects() {
        try {
            equalizer = Equalizer(0, 0).apply {
                enabled = true
            }
            Log.i("ChitauriAudio", "Hardware Equalizer initialized")
        } catch (e: Exception) {
            Log.w("ChitauriAudio", "Equalizer init notice: ${e.message}")
        }
        try {
            bassBoost = BassBoost(0, 0).apply {
                enabled = true
            }
            Log.i("ChitauriAudio", "Hardware BassBoost initialized")
        } catch (e: Exception) {
            Log.w("ChitauriAudio", "BassBoost init notice: ${e.message}")
        }
        try {
            virtualizer = Virtualizer(0, 0).apply {
                enabled = true
            }
            Log.i("ChitauriAudio", "Hardware Virtualizer initialized")
        } catch (e: Exception) {
            Log.w("ChitauriAudio", "Virtualizer init notice: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cancelMediaNotification()
        try {
            mediaSession?.release()
            equalizer?.release()
            bassBoost?.release()
            virtualizer?.release()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
