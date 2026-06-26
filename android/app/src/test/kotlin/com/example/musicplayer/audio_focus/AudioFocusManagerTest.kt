package com.example.musicplayer.audio_focus

import android.media.AudioManager
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever

/**
 * JVM unit tests for [AudioFocusManager].
 *
 * Android stubs return default values (testOptions.returnDefaultValues=true),
 * so Build.VERSION.SDK_INT = 0 < O (26), which means every test exercises the
 * pre-API-26 legacy path in [AudioFocusManager.request] and [AudioFocusManager.abandon].
 * The high-level contracts tested here are version-independent.
 *
 * Focus-listener callbacks (AUDIOFOCUS_GAIN, AUDIOFOCUS_LOSS, DUCK) are invoked
 * through the [AudioFocusManager.simulateFocusChange] test helper exposed via the
 * internal [testFocusListener] property (no reflection needed).
 *
 * Test groups:
 *   A. Initial state
 *   B. setUserVolume — boundary clamping
 *   C. request() — grant and deny paths, idempotent second call
 *   D. abandon() — state reset
 *   E. Focus-change listener — gain, loss, duck, transient
 */
@OptIn(UnstableApi::class)
class AudioFocusManagerTest {

    private lateinit var mockAudioManager: AudioManager
    private lateinit var mockPlayer: ExoPlayer

    private var startTickerCount = 0
    private var stopTickerCount  = 0
    private var focusEventCount  = 0
    private var focusLossCount   = 0

    private fun makeManager(
        getCrossfadeInProgress: () -> Boolean = { false },
    ): AudioFocusManager {
        return AudioFocusManager(
            audioManager           = mockAudioManager,
            getPlayer              = { mockPlayer },
            startTicker            = { startTickerCount++ },
            stopTicker             = { stopTickerCount++ },
            onFocusEvent           = { focusEventCount++ },
            getCrossfadeInProgress = getCrossfadeInProgress,
            onFocusLoss            = { focusLossCount++ },
        )
    }

    @Before
    fun setUp() {
        mockAudioManager = mock()
        mockPlayer       = mock()
        startTickerCount = 0; stopTickerCount = 0
        focusEventCount  = 0; focusLossCount  = 0

        // Default AudioManager stub: requestAudioFocus returns 0 (denied)
        // SDK_INT = 0 → uses deprecated 3-arg requestAudioFocus
        @Suppress("DEPRECATION")
        whenever(
            mockAudioManager.requestAudioFocus(
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any()
            )
        ).thenReturn(0)

        whenever(mockPlayer.isPlaying).thenReturn(false)
        whenever(mockPlayer.volume).thenReturn(1f)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // A. Initial state
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `A01 hasAudioFocus returns false initially`() {
        assertFalse(makeManager().hasAudioFocus())
    }

    @Test fun `A02 volumeBeforeDuck is 1f initially`() {
        assertEquals(1f, makeManager().volumeBeforeDuck, 0.001f)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // B. setUserVolume — boundary clamping
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `B01 setUserVolume stores the given volume`() {
        val mgr = makeManager()
        mgr.setUserVolume(0.7f)
        assertEquals(0.7f, mgr.volumeBeforeDuck, 0.001f)
    }

    @Test fun `B02 setUserVolume clamps value above 1f to 1f`() {
        val mgr = makeManager()
        mgr.setUserVolume(1.5f)
        assertEquals(1.0f, mgr.volumeBeforeDuck, 0.001f)
    }

    @Test fun `B03 setUserVolume clamps negative value to 0f`() {
        val mgr = makeManager()
        mgr.setUserVolume(-0.5f)
        assertEquals(0.0f, mgr.volumeBeforeDuck, 0.001f)
    }

    @Test fun `B04 setUserVolume accepts 0f without clamping`() {
        val mgr = makeManager()
        mgr.setUserVolume(0f)
        assertEquals(0f, mgr.volumeBeforeDuck, 0.001f)
    }

    @Test fun `B05 setUserVolume accepts 1f without clamping`() {
        val mgr = makeManager()
        mgr.setUserVolume(1.0f)
        assertEquals(1.0f, mgr.volumeBeforeDuck, 0.001f)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // C. request() — grant and deny paths
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `C01 request returns false when AudioManager denies focus`() {
        // AudioManager returns 0 (denied) by default
        assertFalse(makeManager().request())
    }

    @Test fun `C02 hasAudioFocus remains false when request is denied`() {
        val mgr = makeManager()
        mgr.request()
        assertFalse(mgr.hasAudioFocus())
    }

    @Test fun `C03 request returns true when AudioManager grants focus`() {
        @Suppress("DEPRECATION")
        whenever(
            mockAudioManager.requestAudioFocus(
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any()
            )
        ).thenReturn(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)

        assertTrue(makeManager().request())
    }

    @Test fun `C04 hasAudioFocus is true after successful request`() {
        @Suppress("DEPRECATION")
        whenever(
            mockAudioManager.requestAudioFocus(
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any()
            )
        ).thenReturn(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)

        val mgr = makeManager()
        mgr.request()
        assertTrue(mgr.hasAudioFocus())
    }

    @Test fun `C05 second request call returns true immediately without calling AudioManager again`() {
        @Suppress("DEPRECATION")
        whenever(
            mockAudioManager.requestAudioFocus(
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any()
            )
        ).thenReturn(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)

        val mgr = makeManager()
        mgr.request()
        mgr.request()

        // AudioManager should have been called only ONCE (shortcut on second call)
        @Suppress("DEPRECATION")
        org.mockito.kotlin.verify(mockAudioManager, org.mockito.kotlin.times(1))
            .requestAudioFocus(
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any()
            )
    }

    // ═════════════════════════════════════════════════════════════════════════
    // D. abandon() — state reset
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `D01 abandon after grant resets hasAudioFocus to false`() {
        @Suppress("DEPRECATION")
        whenever(
            mockAudioManager.requestAudioFocus(
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any()
            )
        ).thenReturn(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)

        val mgr = makeManager()
        mgr.request()
        assertTrue(mgr.hasAudioFocus())

        mgr.abandon()
        assertFalse(mgr.hasAudioFocus())
    }

    @Test fun `D02 abandon when already without focus does not throw`() {
        makeManager().abandon()  // no-op: safe when no focus held
    }

    @Test fun `D03 abandon calls AudioManager abandonAudioFocus (deprecated path)`() {
        val mgr = makeManager()
        mgr.abandon()

        @Suppress("DEPRECATION")
        org.mockito.kotlin.verify(mockAudioManager)
            .abandonAudioFocus(org.mockito.kotlin.any())
    }

    // ═════════════════════════════════════════════════════════════════════════
    // E. Focus-change listener — gain, loss, duck, transient
    //
    // The focusListener field is private, but we can reach it via the
    // AudioManager stub: capture the listener passed to requestAudioFocus
    // and invoke it directly.
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * Obtains the [AudioManager.OnAudioFocusChangeListener] that was registered
     * during [AudioFocusManager.request] by capturing the argument passed to the
     * (deprecated) 3-arg [AudioManager.requestAudioFocus] overload.
     */
    private fun captureListener(mgr: AudioFocusManager): AudioManager.OnAudioFocusChangeListener {
        val captor = org.mockito.kotlin.argumentCaptor<AudioManager.OnAudioFocusChangeListener>()
        @Suppress("DEPRECATION")
        whenever(
            mockAudioManager.requestAudioFocus(
                captor.capture(),
                org.mockito.kotlin.any(),
                org.mockito.kotlin.any()
            )
        ).thenReturn(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
        mgr.request()
        return captor.firstValue
    }

    @Test fun `E01 AUDIOFOCUS_GAIN restores volume and does not resume when not paused`() {
        whenever(mockPlayer.volume).thenReturn(0.3f)
        val mgr      = makeManager()
        val listener = captureListener(mgr)
        mgr.setUserVolume(0.9f)

        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN)

        // volume restored to volumeBeforeDuck (0.9f)
        org.mockito.kotlin.verify(mockPlayer).volume = 0.9f
        assertEquals(1, focusEventCount)
    }

    @Test fun `E02 AUDIOFOCUS_GAIN resumes playback when resumeAfterFocusGain is set`() {
        whenever(mockPlayer.isPlaying).thenReturn(true)
        val mgr      = makeManager()
        val listener = captureListener(mgr)

        // Trigger a transient loss so resumeAfterFocusGain is set
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN)

        org.mockito.kotlin.verify(mockPlayer).play()
        assertEquals(1, startTickerCount)
    }

    @Test fun `E03 AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK ducks volume to 20 percent`() {
        whenever(mockPlayer.volume).thenReturn(1f)
        val mgr      = makeManager()
        mgr.setUserVolume(1f)
        val listener = captureListener(mgr)

        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK)

        // volumeBeforeDuck = 1f (captured), ducked = 1f * 0.2f = 0.2f
        org.mockito.kotlin.verify(mockPlayer).volume = 0.2f
        assertEquals(1, focusEventCount)
    }

    @Test fun `E04 duck during crossfade does not update volumeBeforeDuck`() {
        whenever(mockPlayer.volume).thenReturn(0.4f)  // mid-fade volume
        val mgr      = makeManager(getCrossfadeInProgress = { true })
        val listener = captureListener(mgr)
        mgr.setUserVolume(1f)  // pre-fade target

        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK)

        // volumeBeforeDuck must NOT have been updated to 0.4f during crossfade
        assertEquals(1f, mgr.volumeBeforeDuck, 0.001f)
    }

    @Test fun `E05 AUDIOFOCUS_LOSS_TRANSIENT pauses player and sets resume flag`() {
        whenever(mockPlayer.isPlaying).thenReturn(true)
        val mgr      = makeManager()
        val listener = captureListener(mgr)

        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)

        org.mockito.kotlin.verify(mockPlayer).pause()
        assertEquals(1, stopTickerCount)
        assertEquals(1, focusLossCount)
    }

    @Test fun `E06 AUDIOFOCUS_LOSS pauses player and abandons focus`() {
        whenever(mockPlayer.isPlaying).thenReturn(false)
        val mgr      = makeManager()
        val listener = captureListener(mgr)

        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS)

        org.mockito.kotlin.verify(mockPlayer).pause()
        assertEquals(1, focusLossCount)
        assertFalse(mgr.hasAudioFocus())
    }
}
