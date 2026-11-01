package dev.wndavenz.music.transport

import androidx.media3.exoplayer.ExoPlayer
import dev.wndavenz.music.audio_focus.AudioFocusManager
import dev.wndavenz.music.audio_offload.AudioOffloadManager
import dev.wndavenz.music.crossfade.CrossfadeController
import dev.wndavenz.music.crossfade.PreloadManager
import dev.wndavenz.music.effects.AudioEffectsManager
import dev.wndavenz.music.notification.PlaybackNotificationManager
import dev.wndavenz.music.queue.QueueManager
import dev.wndavenz.music.queue.QueueSync
import dev.wndavenz.music.sleep_timer.SleepTimerManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever

/**
 * Regression tests for crossfade-duration reconfiguration.
 *
 * Dart replans the next AutoMix pair as soon as the incoming deck is promoted,
 * which routinely happens while the previous equal-power fade is still running.
 * A duration update must then apply to the next transition only; it must never
 * tear down the live fade (that path silenced the outgoing deck and jumped the
 * incoming deck to full volume mid-blend).
 */
class TransportCommandsTest {

    private fun commands(
        crossfadeController: CrossfadeController,
        offloadManager: AudioOffloadManager,
        preloadManager: PreloadManager = mock(),
    ): TransportCommands = TransportCommands(
        getPlayer = { mock<ExoPlayer>() },
        audioFocusManager = mock<AudioFocusManager>(),
        crossfadeController = crossfadeController,
        preloadManager = preloadManager,
        queueManager = mock<QueueManager>(),
        queueSync = mock<QueueSync>(),
        transportState = mock(),
        notificationManager = mock<PlaybackNotificationManager>(),
        sleepTimerManager = mock<SleepTimerManager>(),
        effectsManager = mock<AudioEffectsManager>(),
        ensureMediaForeground = {},
        offloadManager = offloadManager,
        playPauseFadeController = mock(),
    )

    @Test
    fun `positive duration change during a fade updates only the next transition`() {
        val crossfade = mock<CrossfadeController>()
        val offload = mock<AudioOffloadManager>()
        val preload = mock<PreloadManager>()
        whenever(crossfade.crossfadeInProgress).thenReturn(true)
        val result = mock<MethodChannel.Result>()

        commands(crossfade, offload, preload).dispatch(
            MethodCall("setCrossfadeDuration", mapOf("duration" to 8.0)),
            result,
        )

        verify(crossfade).setDuration(8f)
        verify(crossfade, never()).cancel(any())
        verify(preload, never()).clearStandbyQueue()
        verify(offload).onCrossfadeDurationChanged(8f)
        verify(result).success(null)
    }

    @Test
    fun `zero duration during a fade still cancels the crossfade`() {
        val crossfade = mock<CrossfadeController>()
        val offload = mock<AudioOffloadManager>()
        val preload = mock<PreloadManager>()
        whenever(crossfade.crossfadeInProgress).thenReturn(true)
        val result = mock<MethodChannel.Result>()

        commands(crossfade, offload, preload).dispatch(
            MethodCall("setCrossfadeDuration", mapOf("duration" to 0.0)),
            result,
        )

        verify(crossfade).setDuration(0f)
        verify(crossfade).cancel(resetVolume = true)
        verify(preload).clearStandbyQueue()
        verify(offload).onCrossfadeDurationChanged(0f)
        verify(result).success(null)
    }

    @Test
    fun `nonfinite duration requests disable crossfade before updating offload policy`() {
        for (duration in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            val crossfade = mock<CrossfadeController>()
            val offload = mock<AudioOffloadManager>()
            val preload = mock<PreloadManager>()
            val result = mock<MethodChannel.Result>()

            commands(crossfade, offload, preload).dispatch(
                MethodCall("setCrossfadeDuration", mapOf("duration" to duration)),
                result,
            )

            verify(crossfade).setDuration(0f)
            verify(crossfade).cancel(resetVolume = true)
            verify(offload).onCrossfadeDurationChanged(0f)
            verify(result).success(null)
        }
    }

    @Test
    fun `finite extreme duration is capped before updating offload policy`() {
        val crossfade = mock<CrossfadeController>()
        val offload = mock<AudioOffloadManager>()
        whenever(crossfade.crossfadeInProgress).thenReturn(true)
        val result = mock<MethodChannel.Result>()

        commands(crossfade, offload).dispatch(
            MethodCall("setCrossfadeDuration", mapOf("duration" to Float.MAX_VALUE.toDouble())),
            result,
        )

        verify(crossfade).setDuration(12f)
        verify(offload).onCrossfadeDurationChanged(12f)
        verify(result).success(null)
    }
}
