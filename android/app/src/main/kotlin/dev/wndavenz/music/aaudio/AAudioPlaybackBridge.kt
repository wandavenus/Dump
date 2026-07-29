package dev.wndavenz.music.aaudio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class AAudioPlaybackBridge(private val context: Context) : EventChannel.StreamHandler {
    @Volatile
    private var sink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    @Volatile
    private var focusRequest: AudioFocusRequest? = null

    private var queue: List<Map<String, Any?>> = emptyList()
    private var index = 0

    @Volatile
    private var decoderThread: Thread? = null

    private val decoding = AtomicBoolean(false)
    private var durationMs = 0L
    private var pendingSeekUs = -1L

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    nativeInit()
                    emitState("idle")
                    result.success(null)
                }

                "setQueue" -> {
                    setQueue(call)
                    result.success(null)
                }

                "setTrack" -> {
                    setTrack(call.argument<Int>("index") ?: 0)
                    result.success(null)
                }

                "skipNext" -> {
                    setTrack((index + 1).coerceAtMost(queue.lastIndex))
                    result.success(null)
                }

                "skipPrevious" -> {
                    setTrack((index - 1).coerceAtLeast(0))
                    result.success(null)
                }

                "play" -> {
                    play()
                    result.success(null)
                }

                "pause" -> {
                    nativePause()
                    emitState("paused")
                    result.success(null)
                }

                "stop" -> {
                    stopDecode()
                    nativeStop()
                    emitState("stopped")
                    result.success(null)
                }

                "seek" -> {
                    pendingSeekUs = (call.argument<Int>("position") ?: 0) * 1000L
                    nativeFlush()
                    result.success(null)
                }

                "setVolume" -> {
                    nativeSetVolume((call.argument<Double>("volume") ?: 1.0).toFloat())
                    result.success(null)
                }

                "dispose" -> {
                    stopDecode()
                    nativeRelease()
                    abandonFocus()
                    emitState("idle")
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            emit(mapOf("type" to "state", "state" to "error", "message" to e.message))
            result.error("aaudio_error", e.message, null)
        }
    }

    private fun setQueue(call: MethodCall) {
        @Suppress("UNCHECKED_CAST")
        queue = call.argument<List<Map<String, Any?>>>("queue") ?: emptyList()
        index = (call.argument<Int>("index") ?: 0).coerceIn(0, (queue.size - 1).coerceAtLeast(0))
        emit(mapOf("type" to "queue", "queue" to queue))
        emitTrack()
    }

    private fun setTrack(next: Int) {
        if (queue.isEmpty()) return
        index = next.coerceIn(0, queue.lastIndex)
        stopDecode()
        emitTrack()
        play()
    }

    private fun play() {
        val song = queue.getOrNull(index) ?: return
        if (!requestFocus()) return

        stopDecode()
        decoding.set(true)

        decoderThread = thread(name = "aaudio-decoder") {
            decode(song["path"] as? String ?: "")
        }

        emitState("buffering")
    }

    private fun decode(path: String) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null

        try {
            extractor.setDataSource(path)

            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalStateException("No audio track")

            extractor.selectTrack(track)

            val inputFormat = extractor.getTrackFormat(track)
            durationMs = inputFormat.getLong(MediaFormat.KEY_DURATION) / 1000L
            emit(mapOf("type" to "duration", "duration" to durationMs))

            val mime = inputFormat.getString(MediaFormat.KEY_MIME)
                ?: throw IllegalStateException("No MIME")

            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(inputFormat, null, null, 0)
                start()
            }

            val info = MediaCodec.BufferInfo()
            var outputConfigured = false
            var sawInputEnd = false
            var sawOutputEnd = false

            while (decoding.get() && !sawOutputEnd) {
                val seekUs = pendingSeekUs
                if (seekUs >= 0) {
                    extractor.seekTo(seekUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                    codec.flush()
                    pendingSeekUs = -1L
                    sawInputEnd = false
                    nativeFlush()
                }

                if (!sawInputEnd) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val input = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inIndex,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            sawInputEnd = true
                        } else {
                            codec.queueInputBuffer(
                                inIndex,
                                0,
                                size,
                                extractor.sampleTime,
                                0
                            )
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                when (outIndex) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val fmt = codec.outputFormat
                        val rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        val channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

                        nativeConfigure(rate, channels)
                        outputConfigured = true

                        emit(
                            mapOf(
                                "type" to "format",
                                "sampleRate" to rate,
                                "channelCount" to channels,
                                "mimeType" to "audio/raw"
                            )
                        )

                        nativeStart()
                        emitState("playing")
                    }

                    else -> {
                        if (outIndex >= 0) {
                            if (!outputConfigured) {
                                throw IllegalStateException("Output format not ready")
                            }

                            val buffer = codec.getOutputBuffer(outIndex) ?: ByteBuffer.allocate(0)
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)

                            nativeWrite(buffer, info.size)

                            emit(
                                mapOf(
                                    "type" to "position",
                                    "position" to info.presentationTimeUs / 1000L
                                )
                            )

                            sawOutputEnd = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                            codec.releaseOutputBuffer(outIndex, false)
                        }
                    }
                }
            }
        } catch (e: Throwable) {
            emit(mapOf("type" to "state", "state" to "error", "message" to e.message))
        } finally {
            try {
                codec?.stop()
            } catch (_: Throwable) {
            }
            try {
                codec?.release()
            } catch (_: Throwable) {
            }
            try {
                extractor.release()
            } catch (_: Throwable) {
            }
            decoding.set(false)
        }
    }

    private fun stopDecode() {
        decoding.set(false)
        decoderThread?.join(500)
        decoderThread = null
    }

    private fun emitTrack() {
        emit(mapOf("type" to "track", "track" to queue.getOrNull(index)?.plus("index" to index)))
    }

    private fun emitState(state: String) {
        emit(mapOf("type" to "state", "state" to state))
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post {
            sink?.success(event)
        }
    }

    private fun requestFocus(): Boolean {
        return if (Build.VERSION.SDK_INT >= 26) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .build()

            focusRequest = req
            audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            true
        }
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= 26) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private external fun nativeInit()
    private external fun nativeConfigure(sampleRate: Int, channels: Int)
    private external fun nativeStart()
    private external fun nativePause()
    private external fun nativeStop()
    private external fun nativeFlush()
    private external fun nativeSetVolume(volume: Float)
    private external fun nativeWrite(buffer: ByteBuffer, size: Int)
    private external fun nativeRelease()

    companion object {
        init {
            System.loadLibrary("aaudio_engine")
        }
    }
}
