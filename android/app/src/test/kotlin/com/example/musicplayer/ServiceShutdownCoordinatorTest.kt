package com.example.musicplayer

import androidx.media3.common.util.UnstableApi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * JVM unit tests for [ServiceShutdownCoordinator].
 *
 * All dependencies are injected as lambda call-counters so no Android
 * framework or Mockito mocking is needed — the coordinator is a plain
 * Kotlin class with no Android imports beyond NativeLogger (which is a
 * no-op in JVM tests because no EventChannel sink is registered).
 *
 * Test groups:
 *   A. Initial state
 *   B. prepareShutdown() — calls the correct Phase-1 lambdas
 *   C. prepareShutdown() idempotency — second call is a no-op
 *   D. performTeardown() — calls the correct Phase-2 lambdas
 *   E. performTeardown() idempotency — second call is a no-op (no double-release)
 *   F. Ordering — prepareShutdown() then performTeardown() (normal "release" flow)
 *   G. System-kill path — performTeardown() without prior prepareShutdown()
 *   H. stop vs release semantic difference (verified via call counts)
 */
@OptIn(UnstableApi::class)
class ServiceShutdownCoordinatorTest {

    // ── Call-counter state ────────────────────────────────────────────────────

    private var cancelCrossfadeCalls:        Int = 0
    private var lastCancelCrossfadeResetVol: Boolean? = null
    private var cancelSleepTimerCalls:       Int = 0
    private var stopPositionTickerCalls:     Int = 0
    private var emitAllCalls:                Int = 0
    private var abandonAudioFocusCalls:      Int = 0
    private var stopForegroundCalls:         Int = 0
    private var saveQueueCalls:              Int = 0
    private var releaseEffectsCalls:         Int = 0
    private var clearHandlerCallbacksCalls:  Int = 0
    private var unregisterReceiversCalls:    Int = 0
    private var releasePrimaryPlayerCalls:   Int = 0
    private var releaseSecondaryPlayerCalls: Int = 0
    private var releaseMediaSessionCalls:    Int = 0

    @Before
    fun setUp() {
        cancelCrossfadeCalls        = 0; lastCancelCrossfadeResetVol = null
        cancelSleepTimerCalls       = 0; stopPositionTickerCalls     = 0
        emitAllCalls                = 0; abandonAudioFocusCalls      = 0
        stopForegroundCalls         = 0; saveQueueCalls              = 0
        releaseEffectsCalls         = 0; clearHandlerCallbacksCalls  = 0
        unregisterReceiversCalls    = 0; releasePrimaryPlayerCalls   = 0
        releaseSecondaryPlayerCalls = 0; releaseMediaSessionCalls    = 0
    }

    private fun makeCoordinator() = ServiceShutdownCoordinator(
        cancelCrossfade        = { rv -> cancelCrossfadeCalls++; lastCancelCrossfadeResetVol = rv },
        cancelSleepTimer       = { cancelSleepTimerCalls++ },
        stopPositionTicker     = { stopPositionTickerCalls++ },
        emitAll                = { emitAllCalls++ },
        abandonAudioFocus      = { abandonAudioFocusCalls++ },
        stopForeground         = { stopForegroundCalls++ },
        saveQueue              = { saveQueueCalls++ },
        releaseEffects         = { releaseEffectsCalls++ },
        clearHandlerCallbacks  = { clearHandlerCallbacksCalls++ },
        unregisterReceivers    = { unregisterReceiversCalls++ },
        releasePrimaryPlayer   = { releasePrimaryPlayerCalls++ },
        releaseSecondaryPlayer = { releaseSecondaryPlayerCalls++ },
        releaseMediaSession    = { releaseMediaSessionCalls++ },
    )

    // ═════════════════════════════════════════════════════════════════════════
    // A. Initial state
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `A01 shutdownPrepared is false initially`() {
        assertFalse(makeCoordinator().shutdownPrepared)
    }

    @Test fun `A02 teardownPerformed is false initially`() {
        assertFalse(makeCoordinator().teardownPerformed)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // B. prepareShutdown() — Phase 1 lambda verification
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `B01 prepareShutdown sets shutdownPrepared to true`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        assertTrue(c.shutdownPrepared)
    }

    @Test fun `B02 prepareShutdown calls cancelSleepTimer`() {
        makeCoordinator().prepareShutdown()
        assertEquals(1, cancelSleepTimerCalls)
    }

    @Test fun `B03 prepareShutdown calls cancelCrossfade with resetVolume=true`() {
        makeCoordinator().prepareShutdown()
        assertEquals(1, cancelCrossfadeCalls)
        assertEquals(true, lastCancelCrossfadeResetVol)
    }

    @Test fun `B04 prepareShutdown calls stopPositionTicker`() {
        makeCoordinator().prepareShutdown()
        assertEquals(1, stopPositionTickerCalls)
    }

    @Test fun `B05 prepareShutdown calls abandonAudioFocus`() {
        makeCoordinator().prepareShutdown()
        assertEquals(1, abandonAudioFocusCalls)
    }

    @Test fun `B06 prepareShutdown calls stopForeground`() {
        makeCoordinator().prepareShutdown()
        assertEquals(1, stopForegroundCalls)
    }

    @Test fun `B07 prepareShutdown calls emitAll`() {
        makeCoordinator().prepareShutdown()
        assertEquals(1, emitAllCalls)
    }

    @Test fun `B08 prepareShutdown does NOT call releaseEffects`() {
        makeCoordinator().prepareShutdown()
        assertEquals(0, releaseEffectsCalls)
    }

    @Test fun `B09 prepareShutdown does NOT release primary player`() {
        makeCoordinator().prepareShutdown()
        assertEquals(0, releasePrimaryPlayerCalls)
    }

    @Test fun `B10 prepareShutdown does NOT release secondary player`() {
        makeCoordinator().prepareShutdown()
        assertEquals(0, releaseSecondaryPlayerCalls)
    }

    @Test fun `B11 prepareShutdown does NOT release media session`() {
        makeCoordinator().prepareShutdown()
        assertEquals(0, releaseMediaSessionCalls)
    }

    @Test fun `B12 prepareShutdown does NOT save the queue`() {
        makeCoordinator().prepareShutdown()
        assertEquals(0, saveQueueCalls)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // C. prepareShutdown() idempotency
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `C01 second prepareShutdown call is a complete no-op`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        c.prepareShutdown()

        assertEquals(1, cancelSleepTimerCalls)
        assertEquals(1, cancelCrossfadeCalls)
        assertEquals(1, stopPositionTickerCalls)
        assertEquals(1, abandonAudioFocusCalls)
        assertEquals(1, stopForegroundCalls)
        assertEquals(1, emitAllCalls)
    }

    @Test fun `C02 shutdownPrepared remains true after second call`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        c.prepareShutdown()
        assertTrue(c.shutdownPrepared)
    }

    @Test fun `C03 three consecutive prepareShutdown calls invoke each lambda once`() {
        val c = makeCoordinator()
        c.prepareShutdown(); c.prepareShutdown(); c.prepareShutdown()
        assertEquals(1, cancelSleepTimerCalls)
        assertEquals(1, emitAllCalls)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // D. performTeardown() — Phase 2 lambda verification
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `D01 performTeardown sets teardownPerformed to true`() {
        val c = makeCoordinator()
        c.performTeardown()
        assertTrue(c.teardownPerformed)
    }

    @Test fun `D02 performTeardown calls cancelCrossfade with resetVolume=true`() {
        makeCoordinator().performTeardown()
        assertEquals(1, cancelCrossfadeCalls)
        assertEquals(true, lastCancelCrossfadeResetVol)
    }

    @Test fun `D03 performTeardown calls saveQueue`() {
        makeCoordinator().performTeardown()
        assertEquals(1, saveQueueCalls)
    }

    @Test fun `D04 performTeardown calls cancelSleepTimer`() {
        makeCoordinator().performTeardown()
        assertEquals(1, cancelSleepTimerCalls)
    }

    @Test fun `D05 performTeardown calls releaseEffects`() {
        makeCoordinator().performTeardown()
        assertEquals(1, releaseEffectsCalls)
    }

    @Test fun `D06 performTeardown calls clearHandlerCallbacks`() {
        makeCoordinator().performTeardown()
        assertEquals(1, clearHandlerCallbacksCalls)
    }

    @Test fun `D07 performTeardown calls unregisterReceivers`() {
        makeCoordinator().performTeardown()
        assertEquals(1, unregisterReceiversCalls)
    }

    @Test fun `D08 performTeardown calls abandonAudioFocus`() {
        makeCoordinator().performTeardown()
        assertEquals(1, abandonAudioFocusCalls)
    }

    @Test fun `D09 performTeardown releases primary player exactly once`() {
        makeCoordinator().performTeardown()
        assertEquals(1, releasePrimaryPlayerCalls)
    }

    @Test fun `D10 performTeardown releases secondary player exactly once`() {
        makeCoordinator().performTeardown()
        assertEquals(1, releaseSecondaryPlayerCalls)
    }

    @Test fun `D11 performTeardown releases media session exactly once`() {
        makeCoordinator().performTeardown()
        assertEquals(1, releaseMediaSessionCalls)
    }

    @Test fun `D12 performTeardown does NOT call stopForeground`() {
        makeCoordinator().performTeardown()
        // stopForeground is Phase-1 only; by onDestroy() the service is already
        // leaving the foreground so calling it again would be a redundant no-op.
        assertEquals(0, stopForegroundCalls)
    }

    @Test fun `D13 performTeardown does NOT call stopPositionTicker`() {
        makeCoordinator().performTeardown()
        assertEquals(0, stopPositionTickerCalls)
    }

    @Test fun `D14 performTeardown does NOT call emitAll`() {
        makeCoordinator().performTeardown()
        assertEquals(0, emitAllCalls)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // E. performTeardown() idempotency — no double-release
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `E01 second performTeardown call is a complete no-op`() {
        val c = makeCoordinator()
        c.performTeardown()
        c.performTeardown()

        assertEquals(1, releasePrimaryPlayerCalls)
        assertEquals(1, releaseSecondaryPlayerCalls)
        assertEquals(1, releaseMediaSessionCalls)
        assertEquals(1, releaseEffectsCalls)
        assertEquals(1, unregisterReceiversCalls)
        assertEquals(1, clearHandlerCallbacksCalls)
        assertEquals(1, abandonAudioFocusCalls)
    }

    @Test fun `E02 teardownPerformed remains true after second call`() {
        val c = makeCoordinator()
        c.performTeardown()
        c.performTeardown()
        assertTrue(c.teardownPerformed)
    }

    @Test fun `E03 three performTeardown calls release each resource exactly once`() {
        val c = makeCoordinator()
        c.performTeardown(); c.performTeardown(); c.performTeardown()
        assertEquals(1, releasePrimaryPlayerCalls)
        assertEquals(1, releaseSecondaryPlayerCalls)
        assertEquals(1, releaseMediaSessionCalls)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // F. Normal "release" flow — prepareShutdown() then performTeardown()
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `F01 prepare then teardown: both phases run`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        c.performTeardown()

        assertTrue(c.shutdownPrepared)
        assertTrue(c.teardownPerformed)
    }

    @Test fun `F02 prepare then teardown: primary player released exactly once`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        c.performTeardown()
        assertEquals(1, releasePrimaryPlayerCalls)
    }

    @Test fun `F03 prepare then teardown: secondary player released exactly once`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        c.performTeardown()
        assertEquals(1, releaseSecondaryPlayerCalls)
    }

    @Test fun `F04 prepare then teardown: media session released exactly once`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        c.performTeardown()
        assertEquals(1, releaseMediaSessionCalls)
    }

    @Test fun `F05 prepare then teardown: effects released exactly once`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        c.performTeardown()
        assertEquals(1, releaseEffectsCalls)
    }

    @Test fun `F06 prepare then teardown: crossfade cancelled in both phases`() {
        // CrossfadeController.cancel() is naturally idempotent — calling it in
        // both Phase 1 and Phase 2 is intentional (Phase 2 handles the system-kill
        // path where Phase 1 may not have run).
        val c = makeCoordinator()
        c.prepareShutdown()    // Phase 1: cancelCrossfade = 1
        c.performTeardown()    // Phase 2: cancelCrossfade = 2
        assertEquals(2, cancelCrossfadeCalls)
    }

    @Test fun `F07 prepare then teardown: abandon audio focus called in both phases`() {
        // AudioFocusManager.abandon() is idempotent — safe to call twice.
        val c = makeCoordinator()
        c.prepareShutdown()
        c.performTeardown()
        assertEquals(2, abandonAudioFocusCalls)
    }

    @Test fun `F08 prepare then extra teardown calls do not double-release`() {
        val c = makeCoordinator()
        c.prepareShutdown()
        c.performTeardown()
        c.performTeardown()  // duplicate — must be a no-op
        c.performTeardown()
        assertEquals(1, releasePrimaryPlayerCalls)
        assertEquals(1, releaseSecondaryPlayerCalls)
        assertEquals(1, releaseMediaSessionCalls)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // G. System-kill path — performTeardown() without prior prepareShutdown()
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `G01 performTeardown without prior prepareShutdown releases all resources`() {
        val c = makeCoordinator()
        c.performTeardown()  // system-kill path — prepareShutdown never ran

        assertEquals(1, releasePrimaryPlayerCalls)
        assertEquals(1, releaseSecondaryPlayerCalls)
        assertEquals(1, releaseMediaSessionCalls)
        assertEquals(1, releaseEffectsCalls)
        assertEquals(1, unregisterReceiversCalls)
        assertEquals(1, clearHandlerCallbacksCalls)
    }

    @Test fun `G02 system-kill teardown also cancels crossfade and sleep timer`() {
        makeCoordinator().performTeardown()
        assertEquals(1, cancelCrossfadeCalls)
        assertEquals(1, cancelSleepTimerCalls)
    }

    @Test fun `G03 system-kill teardown also abandons audio focus`() {
        makeCoordinator().performTeardown()
        assertEquals(1, abandonAudioFocusCalls)
    }

    @Test fun `G04 shutdownPrepared remains false after system-kill teardown`() {
        val c = makeCoordinator()
        c.performTeardown()
        assertFalse(c.shutdownPrepared)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // H. stop vs release semantic difference
    //
    // "stop" does NOT go through ServiceShutdownCoordinator at all —
    // TransportCommands handles it by calling player.stop() which transitions
    // ExoPlayer to STATE_IDLE and abandons focus, but leaves the service alive.
    //
    // "release" calls prepareShutdown() + stopSelf() → onDestroy() calls
    // performTeardown().
    //
    // These tests document the coordinator's role: it is ONLY invoked for
    // the "release" path, never for "stop".  We verify this by confirming
    // that neither phase of the coordinator is invoked unless explicitly called.
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `H01 coordinator not invoked for stop path — no Phase-1 lambdas called`() {
        // Simulates "stop": TransportCommands calls player.stop() directly,
        // never touching ServiceShutdownCoordinator.  Verify clean initial state.
        val c = makeCoordinator()
        // No calls to c.prepareShutdown() or c.performTeardown()
        assertEquals(0, releasePrimaryPlayerCalls)
        assertEquals(0, releaseSecondaryPlayerCalls)
        assertEquals(0, releaseMediaSessionCalls)
        assertEquals(0, releaseEffectsCalls)
        assertFalse(c.shutdownPrepared)
        assertFalse(c.teardownPerformed)
    }

    @Test fun `H02 release path invokes both coordinator phases`() {
        val c = makeCoordinator()
        // Simulate what Media3PlaybackService.handle("release") does:
        c.prepareShutdown()       // → result.success(null); stopSelf()
        c.performTeardown()       // → called by onDestroy()
        assertTrue(c.shutdownPrepared)
        assertTrue(c.teardownPerformed)
        assertEquals(1, releasePrimaryPlayerCalls)
        assertEquals(1, releaseSecondaryPlayerCalls)
        assertEquals(1, releaseMediaSessionCalls)
    }
}
