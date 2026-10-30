package dev.wndavenz.music.transport

import android.os.Handler
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import dev.wndavenz.music.crossfade.CrossfadeController
import dev.wndavenz.music.events.EventEmitter
import dev.wndavenz.music.queue.QueueManager
import dev.wndavenz.music.sleep_timer.SleepTimerManager
import io.flutter.plugin.common.EventChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.mock
import org.mockito.kotlin.times
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever

/** Ensures Flutter engine detach never owns or stops native transport work. */
class TransportStateDetachedEngineTest {
    private class RecordingSink : EventChannel.EventSink {
        val events = mutableListOf<Any?>()
        override fun success(event: Any?) {
            events.add(event)
        }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
        override fun endOfStream() = Unit
    }

    @Test
    fun `detaching Flutter sink leaves playback ticker watchdog and crossfade active`() {
        val engineOwner = Any()
        val sink = RecordingSink()
        EventEmitter.setOnSubscribeCallback { }
        EventEmitter.handler("position", engineOwner).onListen(null, sink)

        val handler = mock<Handler>()
        val player = mock<ExoPlayer>()
        val crossfade = mock<CrossfadeController>()
        val queue = mock<QueueManager>()
        val sleepTimer = mock<SleepTimerManager>()
        val stuckRetries = mutableListOf<Int>()

        whenever(player.isPlaying).thenReturn(true)
        whenever(player.playbackState).thenReturn(Player.STATE_READY)
        whenever(player.currentPosition).thenReturn(10_000L)
        whenever(player.duration).thenReturn(60_000L)
        whenever(crossfade.crossfadeInProgress).thenReturn(false)
        whenever(queue.queue).thenReturn(emptyList())

        val state = TransportState(
            handler = handler,
            getPlayer = { player },
            queueManager = queue,
            crossfadeController = crossfade,
            sleepTimerManager = sleepTimer,
            onStuck = { retry -> stuckRetries.add(retry) },
        )

        state.startPositionTicker()
        val initialTick = argumentCaptor<Runnable>()
        verify(handler).post(initialTick.capture())

        // This is the same cleanup called from MainActivity.cleanUpFlutterEngine.
        EventEmitter.cleanupEngine(engineOwner)

        // The first sample establishes the watchdog baseline; the remaining 25
        // samples account for 5 seconds of a stalled-but-playing player.
        repeat(26) { initialTick.firstValue.run() }

        assertTrue("native player must remain in playback", player.isPlaying)
        assertTrue("detached sink must not receive ticker events", sink.events.isEmpty())
        assertEquals("watchdog must still recover a stalled player", listOf(1), stuckRetries)
        verify(crossfade, times(26)).maybeCrossfadeOut()
        verify(handler, times(26)).postDelayed(initialTick.firstValue, 200L)
    }
}
