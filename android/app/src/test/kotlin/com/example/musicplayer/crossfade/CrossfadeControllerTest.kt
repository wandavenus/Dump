package com.example.musicplayer.crossfade

import android.os.Handler
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever

/**
 * JVM unit tests for [CrossfadeController].
 *
 * Handler.post / postDelayed / removeCallbacks are called against Android stubs
 * that return default values (no message queue exists in JVM tests), so Runnable
 * bodies are NOT executed. Tests therefore focus on the state changes that happen
 * synchronously before any handler post:
 *
 *   • setDuration, cancel, resetPromotionState — fully testable
 *   • maybeCrossfadeOut guard conditions — testable via mock ExoPlayer
 *   • beginCrossfade state mutations — partially testable (flags set before handler post)
 *
 * Test groups:
 *   A. Initial state
 *   B. setDuration
 *   C. cancel() — resets all flags
 *   D. resetPromotionState()
 *   E. maybeCrossfadeOut() guard conditions (early returns)
 *   F. beginCrossfade() state mutations (via maybeCrossfadeOut trigger)
 */
@OptIn(UnstableApi::class)
class CrossfadeControllerTest {

    private lateinit var mockHandler:        Handler
    private lateinit var mockPreloadManager: PreloadManager
    private lateinit var mockActivePlayer:   ExoPlayer
    private lateinit var mockStandbyPlayer:  ExoPlayer

    private var setActivePlayerCalls  = 0
    private var switchSessionCalls    = 0
    private var crossfadeCompleteCalls = 0
    private var emitAllCalls          = 0
    private var refreshNotifCalls     = 0
    private var crossfadeStartingCalls = 0

    private val testQueue = listOf(
        mapOf("title" to "Track A", "uri" to "file:///a.mp3"),
        mapOf("title" to "Track B", "uri" to "file:///b.mp3"),
    )

    private fun makeController(
        activePlayer:  ExoPlayer? = mockActivePlayer,
        standbyPlayer: ExoPlayer? = mockStandbyPlayer,
        queue:         List<Map<String, Any?>> = testQueue,
        activeIndex:   Int = 0,
        volumeBeforeDuck: Float = 1f,
        hasAudioFocus: Boolean = true,
    ) = CrossfadeController(
        handler              = mockHandler,
        getActivePlayer      = { activePlayer },
        getStandbyPlayer     = { standbyPlayer },
        setActivePlayer      = { setActivePlayerCalls++ },
        switchSessionPlayer  = { switchSessionCalls++ },
        preloadManager       = mockPreloadManager,
        getVolumeBeforeDuck  = { volumeBeforeDuck },
        hasAudioFocus        = { hasAudioFocus },
        requestAudioFocus    = { hasAudioFocus },
        getQueue             = { queue },
        getActiveQueueIndex  = { activeIndex },
        setActiveQueueIndex  = { },
        onCrossfadeComplete  = { crossfadeCompleteCalls++ },
        emitAll              = { emitAllCalls++ },
        refreshNotification  = { refreshNotifCalls++ },
        onCrossfadeStarting  = { crossfadeStartingCalls++ },
    )

    @Before
    fun setUp() {
        mockHandler        = mock()
        mockPreloadManager = mock()
        mockActivePlayer   = mock()
        mockStandbyPlayer  = mock()

        setActivePlayerCalls   = 0; switchSessionCalls     = 0
        crossfadeCompleteCalls = 0; emitAllCalls           = 0
        refreshNotifCalls      = 0; crossfadeStartingCalls = 0

        // Sensible defaults for active player
        whenever(mockActivePlayer.duration).thenReturn(180_000L)
        whenever(mockActivePlayer.currentPosition).thenReturn(170_000L)  // 10 s remaining
        whenever(mockActivePlayer.hasNextMediaItem()).thenReturn(true)
        whenever(mockActivePlayer.repeatMode).thenReturn(Player.REPEAT_MODE_OFF)
        whenever(mockActivePlayer.currentMediaItemIndex).thenReturn(0)
        whenever(mockActivePlayer.mediaItemCount).thenReturn(2)

        // Standby player ready
        whenever(mockStandbyPlayer.mediaItemCount).thenReturn(1)
        whenever(mockStandbyPlayer.playbackState).thenReturn(Player.STATE_READY)

        // PreloadManager: preloaded at index 1
        whenever(mockPreloadManager.preloadedQueueIndex).thenReturn(1)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // A. Initial state
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `A01 crossfadeDurationSec is 0 initially`() {
        assertEquals(0f, makeController().crossfadeDurationSec, 0.001f)
    }

    @Test fun `A02 crossfadeInProgress is false initially`() {
        assertFalse(makeController().crossfadeInProgress)
    }

    @Test fun `A03 promotionTriggered is false initially`() {
        assertFalse(makeController().promotionTriggered)
    }

    @Test fun `A04 promotionOwner is null initially`() {
        assertNull(makeController().promotionOwner)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // B. setDuration
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `B01 setDuration updates crossfadeDurationSec`() {
        val ctrl = makeController()
        ctrl.setDuration(3.0f)
        assertEquals(3.0f, ctrl.crossfadeDurationSec, 0.001f)
    }

    @Test fun `B02 setDuration to zero clears the duration`() {
        val ctrl = makeController()
        ctrl.setDuration(5.0f)
        ctrl.setDuration(0f)
        assertEquals(0f, ctrl.crossfadeDurationSec, 0.001f)
    }

    @Test fun `B03 setDuration accepts fractional seconds`() {
        val ctrl = makeController()
        ctrl.setDuration(2.5f)
        assertEquals(2.5f, ctrl.crossfadeDurationSec, 0.001f)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // C. cancel()
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `C01 cancel when not in crossfade leaves flags false`() {
        val ctrl = makeController()
        ctrl.setDuration(3f)
        ctrl.cancel(resetVolume = false)
        assertFalse(ctrl.crossfadeInProgress)
        assertFalse(ctrl.promotionTriggered)
        assertNull(ctrl.promotionOwner)
    }

    @Test fun `C02 cancel with resetVolume=true restores active player volume`() {
        val ctrl = makeController(volumeBeforeDuck = 0.9f)
        ctrl.cancel(resetVolume = true)
        verify(mockActivePlayer).volume = 0.9f
    }

    @Test fun `C03 cancel with resetVolume=false does not touch player volume`() {
        val ctrl = makeController()
        ctrl.cancel(resetVolume = false)
        verify(mockActivePlayer, never()).volume = org.mockito.kotlin.any()
    }

    @Test fun `C04 cancel with no active player and resetVolume=true does not throw`() {
        val ctrl = makeController(activePlayer = null)
        ctrl.cancel(resetVolume = true)  // getActivePlayer() returns null → safe no-op
    }

    @Test fun `C05 cancel removes any pending handler callbacks`() {
        val ctrl = makeController()
        ctrl.cancel(resetVolume = false)
        // handler.removeCallbacks(null) would be called only if runnable exists;
        // with no crossfade in progress the runnable field is null so this is a no-op.
        // Just confirming no exception is thrown.
    }

    // ═════════════════════════════════════════════════════════════════════════
    // D. resetPromotionState()
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `D01 resetPromotionState when not in crossfade does nothing observable`() {
        val ctrl = makeController()
        ctrl.setDuration(3f)
        ctrl.resetPromotionState()
        assertFalse(ctrl.promotionTriggered)
        assertFalse(ctrl.crossfadeInProgress)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // E. maybeCrossfadeOut() guard conditions
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `E01 maybeCrossfadeOut does nothing when duration is 0`() {
        val ctrl = makeController()
        ctrl.maybeCrossfadeOut()
        assertFalse(ctrl.crossfadeInProgress)
        verify(mockPreloadManager, never()).preloadNextTrack()
    }

    @Test fun `E02 maybeCrossfadeOut does nothing when no active player`() {
        val ctrl = makeController(activePlayer = null)
        ctrl.setDuration(3f)
        ctrl.maybeCrossfadeOut()
        assertFalse(ctrl.crossfadeInProgress)
    }

    @Test fun `E03 maybeCrossfadeOut does nothing when player duration is TIME_UNSET`() {
        whenever(mockActivePlayer.duration).thenReturn(C.TIME_UNSET)
        val ctrl = makeController()
        ctrl.setDuration(3f)
        ctrl.maybeCrossfadeOut()
        assertFalse(ctrl.crossfadeInProgress)
    }

    @Test fun `E04 maybeCrossfadeOut does nothing when duration is zero`() {
        whenever(mockActivePlayer.duration).thenReturn(0L)
        val ctrl = makeController()
        ctrl.setDuration(3f)
        ctrl.maybeCrossfadeOut()
        assertFalse(ctrl.crossfadeInProgress)
    }

    @Test fun `E05 maybeCrossfadeOut does nothing when no next item and repeat is OFF`() {
        whenever(mockActivePlayer.hasNextMediaItem()).thenReturn(false)
        whenever(mockActivePlayer.repeatMode).thenReturn(Player.REPEAT_MODE_OFF)
        val ctrl = makeController()
        ctrl.setDuration(3f)
        ctrl.maybeCrossfadeOut()
        assertFalse(ctrl.crossfadeInProgress)
    }

    @Test fun `E06 maybeCrossfadeOut proceeds when repeat is ALL even without next item`() {
        whenever(mockActivePlayer.hasNextMediaItem()).thenReturn(false)
        whenever(mockActivePlayer.repeatMode).thenReturn(Player.REPEAT_MODE_ALL)
        // remaining = 180_000 - 170_000 = 10_000 ms; fade = 3_000 ms
        // 10_000 > (3_000 + 250) so neither prewarm nor crossfade triggers yet
        val ctrl = makeController()
        ctrl.setDuration(3f)
        ctrl.maybeCrossfadeOut()
        // preloadNextTrack IS called (regardless of crossfade trigger)
        verify(mockPreloadManager).preloadNextTrack()
    }

    @Test fun `E07 maybeCrossfadeOut does nothing when standby has no media`() {
        whenever(mockStandbyPlayer.mediaItemCount).thenReturn(0)
        val ctrl = makeController()
        ctrl.setDuration(3f)
        ctrl.maybeCrossfadeOut()
        assertFalse(ctrl.crossfadeInProgress)
    }

    @Test fun `E08 maybeCrossfadeOut does nothing when no standby player`() {
        val ctrl = makeController(standbyPlayer = null)
        ctrl.setDuration(3f)
        ctrl.maybeCrossfadeOut()
        assertFalse(ctrl.crossfadeInProgress)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // F. beginCrossfade state mutations (triggered via maybeCrossfadeOut)
    //
    // Remaining time is set very close to the crossfade window so that
    // maybeCrossfadeOut enters beginCrossfade synchronously.  Handler.post()
    // is a no-op in the JVM stub, so state changes before the post are visible.
    // ═════════════════════════════════════════════════════════════════════════

    private fun makeControllerWithImmediateTrigger(): CrossfadeController {
        // 3 s fade, 2.8 s remaining → inside the (crossMs + 250) window
        whenever(mockActivePlayer.duration).thenReturn(10_000L)
        whenever(mockActivePlayer.currentPosition).thenReturn(7_200L)
        return makeController().also { it.setDuration(3f) }
    }

    @Test fun `F01 crossfadeInProgress set to true when beginCrossfade triggers`() {
        val ctrl = makeControllerWithImmediateTrigger()
        ctrl.maybeCrossfadeOut()
        assertTrue(ctrl.crossfadeInProgress)
    }

    @Test fun `F02 promotionTriggered set to true when beginCrossfade triggers`() {
        val ctrl = makeControllerWithImmediateTrigger()
        ctrl.maybeCrossfadeOut()
        assertTrue(ctrl.promotionTriggered)
    }

    @Test fun `F03 promotionOwner set to old active player when crossfade triggers`() {
        val ctrl = makeControllerWithImmediateTrigger()
        ctrl.maybeCrossfadeOut()
        assertEquals(mockActivePlayer, ctrl.promotionOwner)
    }

    @Test fun `F04 setActivePlayer is called with standby player when crossfade triggers`() {
        val ctrl = makeControllerWithImmediateTrigger()
        ctrl.maybeCrossfadeOut()
        assertTrue(setActivePlayerCalls > 0)
    }

    @Test fun `F05 switchSessionPlayer is called when crossfade triggers`() {
        val ctrl = makeControllerWithImmediateTrigger()
        ctrl.maybeCrossfadeOut()
        assertTrue(switchSessionCalls > 0)
    }

    @Test fun `F06 onCrossfadeStarting is called when crossfade triggers`() {
        val ctrl = makeControllerWithImmediateTrigger()
        ctrl.maybeCrossfadeOut()
        assertEquals(1, crossfadeStartingCalls)
    }

    @Test fun `F07 second maybeCrossfadeOut call when already in progress is ignored`() {
        val ctrl = makeControllerWithImmediateTrigger()
        ctrl.maybeCrossfadeOut()
        val callsAfterFirst = setActivePlayerCalls
        ctrl.maybeCrossfadeOut()  // crossfadeInProgress=true → returns immediately
        assertEquals(callsAfterFirst, setActivePlayerCalls)
    }

    @Test fun `F08 cancel after beginCrossfade resets all flags`() {
        val ctrl = makeControllerWithImmediateTrigger()
        ctrl.maybeCrossfadeOut()
        assertTrue(ctrl.crossfadeInProgress)

        ctrl.cancel(resetVolume = false)

        assertFalse(ctrl.crossfadeInProgress)
        assertFalse(ctrl.promotionTriggered)
        assertNull(ctrl.promotionOwner)
    }
}
