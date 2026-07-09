package com.example.musicplayer

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.Window
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.SeekBar
import android.widget.TextView
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture

/**
 * A translucent floating Activity that shows a compact "now playing" preview
 * when the user opens an audio file from a file manager or another app.
 *
 * The Activity is dialog-themed so the originating app (ZArchiver, Telegram, etc.)
 * remains visible behind the card. The user never has to leave their file manager.
 *
 * Flow:
 *   1. Reads metadata (title / artist / art) on a background thread.
 *   2. Starts Media3PlaybackService via ACTION_PLAY_URI.
 *   3. Connects a MediaController for live position / play-state polling.
 *   4. "Open in App" button launches MainActivity and finishes this Activity.
 */
class NowPlayingOverlayActivity : Activity() {

    // ── UI ────────────────────────────────────────────────────────────────────
    private lateinit var ivArt:      ImageView
    private lateinit var tvTitle:    TextView
    private lateinit var tvArtist:   TextView
    private lateinit var btnPP:      ImageButton
    private lateinit var seekBar:    SeekBar
    private lateinit var tvElapsed:  TextView
    private lateinit var tvDuration: TextView

    // ── Playback ──────────────────────────────────────────────────────────────
    private val handler = Handler(Looper.getMainLooper())
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    private var connectRetries = 0
    private var isOpeningMainApp = false
    
    // ── Progress ticker ───────────────────────────────────────────────────────
    private val ticker = object : Runnable {
        override fun run() {
            val ctrl = controller ?: return
            val pos  = ctrl.currentPosition.coerceAtLeast(0)
            val dur  = ctrl.duration.let { if (it < 0) 0L else it }
            if (dur > 0) {
                seekBar.max      = dur.toInt()
                seekBar.progress = pos.toInt()
            }
            tvElapsed.text  = formatMs(pos)
            tvDuration.text = formatMs(dur)
            btnPP.setImageResource(
                if (ctrl.isPlaying) R.drawable.ic_pause else R.drawable.ic_play
            )
            handler.postDelayed(this, 500)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        setContentView(R.layout.activity_now_playing_overlay)

        val uriStr = extractAudioUri(intent) ?: run { finish(); return }

        bindViews()
        wireListeners(uriStr)
        loadAndPlay(uriStr)
    }

    private fun bindViews() {
        ivArt      = findViewById(R.id.ivAlbumArt)
        tvTitle    = findViewById(R.id.tvTitle)
        tvArtist   = findViewById(R.id.tvArtist)
        btnPP      = findViewById(R.id.btnPlayPause)
        seekBar    = findViewById(R.id.seekBar)
        tvElapsed  = findViewById(R.id.tvElapsed)
        tvDuration = findViewById(R.id.tvDuration)
    }

    private fun wireListeners(uriStr: String) {
        // Tap the scrim → dismiss
        findViewById<View>(R.id.scrim).setOnClickListener { finish() }
        // Card itself doesn't propagate taps to scrim
        findViewById<View>(R.id.card).setOnClickListener {}

        btnPP.setOnClickListener {
            controller?.let { if (it.isPlaying) it.pause() else it.play() }
        }

        seekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, p: Int, fromUser: Boolean) {
                if (fromUser) controller?.seekTo(p.toLong())
            }
            override fun onStartTrackingTouch(sb: SeekBar?) {}
            override fun onStopTrackingTouch(sb: SeekBar?) {}
        })

        val openLabel = getString(R.string.overlay_open_in_app, getString(R.string.app_name))
        findViewById<TextView>(R.id.tvOpenApp).text = openLabel

                findViewById<View>(R.id.btnOpenApp).setOnClickListener {
            isOpeningMainApp = true // <── Tambahin ini biar pas buka app, musik ga mati
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
            )
            finish()
        }

    }

    // ── Load metadata + start playback ────────────────────────────────────────
    private fun loadAndPlay(uriStr: String) {
        Thread {
            val (title, artist, art) = readMeta(uriStr)
            startPlaybackService(uriStr)
            handler.post {
                tvTitle.text  = title
                tvArtist.text = artist
                if (art != null) ivArt.setImageBitmap(art)
                connectController()
            }
        }.start()
    }

            private fun startPlaybackService(uriStr: String) {
        val svcIntent = Intent(this, Media3PlaybackService::class.java).apply {
            action = Media3PlaybackService.ACTION_PLAY_URI
            putExtra(Media3PlaybackService.EXTRA_URI, uriStr)
            // ── Tambahin baris di bawah ini ──
            putExtra("IS_OVERLAY_PREVIEW", true) 
        }
        
        // Tetep pake startService biasa biar sistem ga maksa bikin foreground notification
        startService(svcIntent) 
    }



    // ── MediaController ───────────────────────────────────────────────────────
    private fun connectController() {
        val token = SessionToken(this, ComponentName(this, Media3PlaybackService::class.java))
        val future = MediaController.Builder(this, token).buildAsync()
        controllerFuture = future
        future.addListener({
            try {
                controller = future.get()
                connectRetries = 0
                handler.post(ticker)
            } catch (e: Exception) {
                // Service may still be warming up on cold start — use bounded
                // exponential backoff: 500 ms → 750 ms → ... up to ~8 s total.
                if (++connectRetries <= 12) {
                    val delay = (500L * connectRetries).coerceAtMost(1500L)
                    handler.postDelayed({ connectController() }, delay)
                }
            }
        }, mainExecutor)
    }

        // ── Lifecycle ─────────────────────────────────────────────────────────────
    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controller = null

        // Kalau user pencet luar (bukan pencet tombol Open App)
        if (!isOpeningMainApp) {
            try {
                // Matiin service musiknya
                val svcIntent = Intent(this, Media3PlaybackService::class.java)
                stopService(svcIntent)
            } catch (_: Exception) {}
            
            // Kill total aplikasi biar ga nggantung di background
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }


    // ── Helpers ───────────────────────────────────────────────────────────────
    private data class Meta(val title: String, val artist: String, val art: Bitmap?)

    private fun readMeta(uriStr: String): Meta {
        // Fallback title from filename
        var title  = uriStr.substringAfterLast('/').let {
            if (it.contains('?')) it.substringBefore('?') else it
        }.let { if (it.contains('.')) it.substringBeforeLast('.') else it }
            .ifBlank { "Unknown Title" }
        var artist = "Unknown Artist"
        var art: Bitmap? = null

        try {
            val r = MediaMetadataRetriever()
            if (uriStr.startsWith("content://")) {
                r.setDataSource(applicationContext, Uri.parse(uriStr))
            } else {
                val path = if (uriStr.startsWith("file://"))
                    Uri.parse(uriStr).path ?: uriStr else uriStr
                r.setDataSource(path)
            }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                ?.takeIf { it.isNotBlank() }?.let { title = it }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                ?.takeIf { it.isNotBlank() }?.let { artist = it }
            r.embeddedPicture?.let { bytes ->
                art = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
            r.release()
        } catch (_: Exception) {}

        return Meta(title, artist, art)
    }

    private fun extractAudioUri(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri    = intent.data ?: return null
        val scheme = uri.scheme ?: ""
        val mime   = intent.type ?: contentResolver.getType(uri) ?: ""
        return when {
            mime.startsWith("audio/") -> uri.toString()
            scheme == "content"       -> null
            scheme == "file" || scheme.isEmpty() -> {
                val ext = uri.lastPathSegment?.substringAfterLast('.')?.lowercase() ?: ""
                if (ext in AUDIO_EXTENSIONS) uri.toString() else null
            }
            else -> null
        }
    }

    private fun formatMs(ms: Long): String {
        val s = (ms / 1000).toInt()
        return "%d:%02d".format(s / 60, s % 60)
    }

    companion object {
        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "flac", "wav", "ogg", "opus", "aac", "m4a", "m4b",
            "wma", "aiff", "aif", "ape", "mka", "dsf", "dff", "alac"
        )
    }
}
