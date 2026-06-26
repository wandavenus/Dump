package com.example.musicplayer

import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever

/**
 * JVM unit tests for [ActivePlayerProxy].
 *
 * Verifies the core contract: every overridden [Player] getter always delegates
 * to [_current] (the argument last passed to [ActivePlayerProxy.switchTo], or
 * the initial player before any switch), so no caller can ever observe a mixed
 * snapshot where fields originate from two different ExoPlayer instances.
 *
 * Test groups:
 *   A. Core position snapshot (timeline, period, state, position)
 *   B. Queue / timeline fields (mediaItemCount, indices, has-next/prev)
 *   C. Buffer accounting (bufferedPosition, contentPosition, ad state)
 *   D. Tracks and metadata
 *   E. Playback parameters and control flags
 *   F. Commands and output (availableCommands, videoSize, cues)
 *   G. switchTo() behaviour (no-op, consecutive, listener migration)
 *   H. Transport command lambda delegation
 *   I. seekTo() routing (INDEX_UNSET, same index, queue jump)
 */
@OptIn(UnstableApi::class)
class ActivePlayerProxyTest {

    private lateinit var p1: ExoPlayer
    private lateinit var p2: ExoPlayer

    // Transport command capture
    private var playCount     = 0
    private var pauseCount    = 0
    private var skipNextCount = 0
    private var skipPrevCount = 0
    private var lastSeekMs    = -1L
    private var lastSetTrack  = -1

    // Distinct mock objects for reference-equality assertions
    private lateinit var timeline1: Timeline
    private lateinit var timeline2: Timeline
    private lateinit var tracks1: Tracks
    private lateinit var tracks2: Tracks
    private lateinit var tsp1: TrackSelectionParameters
    private lateinit var tsp2: TrackSelectionParameters
    private lateinit var meta1: MediaMetadata
    private lateinit var meta2: MediaMetadata
    private lateinit var pp1: PlaybackParameters
    private lateinit var pp2: PlaybackParameters
    private lateinit var cmds1: Player.Commands
    private lateinit var cmds2: Player.Commands
    private lateinit var vs1: VideoSize
    private lateinit var vs2: VideoSize
    private lateinit var cg1: CueGroup
    private lateinit var cg2: CueGroup
    private lateinit var mi1: MediaItem
    private lateinit var mi2: MediaItem

    private fun buildProxy(initial: ExoPlayer = p1) = ActivePlayerProxy(
        initialPlayer = initial,
        onPlay        = { playCount++ },
        onPause       = { pauseCount++ },
        onSkipNext    = { skipNextCount++ },
        onSkipPrev    = { skipPrevCount++ },
        onSeek        = { lastSeekMs = it },
        onSetTrack    = { lastSetTrack = it },
    )

    @Before
    fun setUp() {
        p1 = mock()
        p2 = mock()
        timeline1 = mock(); timeline2 = mock()
        tracks1   = mock(); tracks2   = mock()
        tsp1      = mock(); tsp2      = mock()
        meta1     = mock(); meta2     = mock()
        pp1       = mock(); pp2       = mock()
        cmds1     = mock(); cmds2     = mock()
        vs1       = mock(); vs2       = mock()
        cg1       = mock(); cg2       = mock()
        mi1       = mock(); mi2       = mock()

        playCount = 0; pauseCount = 0; skipNextCount = 0; skipPrevCount = 0
        lastSeekMs = -1L; lastSetTrack = -1

        // Stub p1 — distinctive non-default values
        whenever(p1.currentTimeline).thenReturn(timeline1)
        whenever(p1.currentPeriodIndex).thenReturn(3)
        whenever(p1.isPlaying).thenReturn(true)
        whenever(p1.playbackState).thenReturn(Player.STATE_READY)
        whenever(p1.currentMediaItemIndex).thenReturn(7)
        whenever(p1.currentMediaItem).thenReturn(mi1)
        whenever(p1.currentPosition).thenReturn(12_345L)
        whenever(p1.duration).thenReturn(180_000L)
        whenever(p1.bufferedPosition).thenReturn(60_000L)
        whenever(p1.isLoading).thenReturn(true)
        whenever(p1.volume).thenReturn(0.8f)
        whenever(p1.playbackSuppressionReason).thenReturn(1)
        whenever(p1.playWhenReady).thenReturn(true)
        whenever(p1.playerError).thenReturn(null)
        whenever(p1.mediaItemCount).thenReturn(10)
        whenever(p1.nextMediaItemIndex).thenReturn(8)
        whenever(p1.previousMediaItemIndex).thenReturn(6)
        whenever(p1.hasNextMediaItem()).thenReturn(true)
        whenever(p1.hasPreviousMediaItem()).thenReturn(true)
        whenever(p1.totalBufferedDuration).thenReturn(47_655L)
        whenever(p1.contentPosition).thenReturn(11_111L)
        whenever(p1.contentBufferedPosition).thenReturn(55_555L)
        whenever(p1.contentDuration).thenReturn(179_000L)
        whenever(p1.isPlayingAd).thenReturn(false)
        whenever(p1.currentAdGroupIndex).thenReturn(C.INDEX_UNSET)
        whenever(p1.currentAdIndexInAdGroup).thenReturn(C.INDEX_UNSET)
        whenever(p1.currentTracks).thenReturn(tracks1)
        whenever(p1.trackSelectionParameters).thenReturn(tsp1)
        whenever(p1.mediaMetadata).thenReturn(meta1)
        whenever(p1.playlistMetadata).thenReturn(meta1)
        whenever(p1.playbackParameters).thenReturn(pp1)
        whenever(p1.repeatMode).thenReturn(Player.REPEAT_MODE_ALL)
        whenever(p1.shuffleModeEnabled).thenReturn(true)
        whenever(p1.seekBackIncrement).thenReturn(15_000L)
        whenever(p1.seekForwardIncrement).thenReturn(30_000L)
        whenever(p1.maxSeekToPreviousPosition).thenReturn(3_000L)
        whenever(p1.availableCommands).thenReturn(cmds1)
        whenever(p1.videoSize).thenReturn(vs1)
        whenever(p1.currentCues).thenReturn(cg1)
        whenever(p1.isCommandAvailable(any())).thenReturn(true)
        whenever(p1.getMediaItemAt(7)).thenReturn(mi1)

        // Stub p2 — all values differ from p1
        whenever(p2.currentTimeline).thenReturn(timeline2)
        whenever(p2.currentPeriodIndex).thenReturn(0)
        whenever(p2.isPlaying).thenReturn(false)
        whenever(p2.playbackState).thenReturn(Player.STATE_BUFFERING)
        whenever(p2.currentMediaItemIndex).thenReturn(0)
        whenever(p2.currentMediaItem).thenReturn(mi2)
        whenever(p2.currentPosition).thenReturn(0L)
        whenever(p2.duration).thenReturn(300_000L)
        whenever(p2.bufferedPosition).thenReturn(5_000L)
        whenever(p2.isLoading).thenReturn(false)
        whenever(p2.volume).thenReturn(0f)
        whenever(p2.playbackSuppressionReason).thenReturn(0)
        whenever(p2.playWhenReady).thenReturn(false)
        whenever(p2.playerError).thenReturn(null)
        whenever(p2.mediaItemCount).thenReturn(1)
        whenever(p2.nextMediaItemIndex).thenReturn(C.INDEX_UNSET)
        whenever(p2.previousMediaItemIndex).thenReturn(C.INDEX_UNSET)
        whenever(p2.hasNextMediaItem()).thenReturn(false)
        whenever(p2.hasPreviousMediaItem()).thenReturn(false)
        whenever(p2.totalBufferedDuration).thenReturn(5_000L)
        whenever(p2.contentPosition).thenReturn(0L)
        whenever(p2.contentBufferedPosition).thenReturn(5_000L)
        whenever(p2.contentDuration).thenReturn(300_000L)
        whenever(p2.isPlayingAd).thenReturn(false)
        whenever(p2.currentAdGroupIndex).thenReturn(C.INDEX_UNSET)
        whenever(p2.currentAdIndexInAdGroup).thenReturn(C.INDEX_UNSET)
        whenever(p2.currentTracks).thenReturn(tracks2)
        whenever(p2.trackSelectionParameters).thenReturn(tsp2)
        whenever(p2.mediaMetadata).thenReturn(meta2)
        whenever(p2.playlistMetadata).thenReturn(meta2)
        whenever(p2.playbackParameters).thenReturn(pp2)
        whenever(p2.repeatMode).thenReturn(Player.REPEAT_MODE_OFF)
        whenever(p2.shuffleModeEnabled).thenReturn(false)
        whenever(p2.seekBackIncrement).thenReturn(10_000L)
        whenever(p2.seekForwardIncrement).thenReturn(10_000L)
        whenever(p2.maxSeekToPreviousPosition).thenReturn(2_000L)
        whenever(p2.availableCommands).thenReturn(cmds2)
        whenever(p2.videoSize).thenReturn(vs2)
        whenever(p2.currentCues).thenReturn(cg2)
        whenever(p2.isCommandAvailable(any())).thenReturn(false)
        whenever(p2.getMediaItemAt(0)).thenReturn(mi2)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // A. Core position snapshot
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `A01 getWrappedPlayer returns initialPlayer before switchTo`() {
        val proxy = buildProxy()
        assertSame(p1, proxy.wrappedPlayer)
    }

    @Test fun `A02 getWrappedPlayer returns new player after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(p2, proxy.wrappedPlayer)
    }

    @Test fun `A03 currentTimeline delegates to initialPlayer`() {
        assertSame(timeline1, buildProxy().currentTimeline)
    }

    @Test fun `A04 currentTimeline switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(timeline2, proxy.currentTimeline)
    }

    @Test fun `A05 currentPeriodIndex delegates to initialPlayer`() {
        assertEquals(3, buildProxy().currentPeriodIndex)
    }

    @Test fun `A06 currentPeriodIndex switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(0, proxy.currentPeriodIndex)
    }

    @Test fun `A07 isPlaying delegates to initialPlayer`() {
        assertTrue(buildProxy().isPlaying)
    }

    @Test fun `A08 isPlaying switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertFalse(proxy.isPlaying)
    }

    @Test fun `A09 playbackState delegates to initialPlayer`() {
        assertEquals(Player.STATE_READY, buildProxy().playbackState)
    }

    @Test fun `A10 playbackState switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(Player.STATE_BUFFERING, proxy.playbackState)
    }

    @Test fun `A11 currentMediaItemIndex delegates to initialPlayer`() {
        assertEquals(7, buildProxy().currentMediaItemIndex)
    }

    @Test fun `A12 currentMediaItemIndex switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(0, proxy.currentMediaItemIndex)
    }

    @Test fun `A13 currentPosition delegates to initialPlayer`() {
        assertEquals(12_345L, buildProxy().currentPosition)
    }

    @Test fun `A14 currentPosition switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(0L, proxy.currentPosition)
    }

    @Test fun `A15 duration delegates to initialPlayer`() {
        assertEquals(180_000L, buildProxy().duration)
    }

    @Test fun `A16 duration switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(300_000L, proxy.duration)
    }

    @Test fun `A17 bufferedPosition delegates to initialPlayer`() {
        assertEquals(60_000L, buildProxy().bufferedPosition)
    }

    @Test fun `A18 isLoading delegates to initialPlayer`() {
        assertTrue(buildProxy().isLoading)
    }

    @Test fun `A19 volume delegates to initialPlayer`() {
        assertEquals(0.8f, buildProxy().volume, 0.001f)
    }

    @Test fun `A20 playbackSuppressionReason delegates to initialPlayer`() {
        assertEquals(1, buildProxy().playbackSuppressionReason)
    }

    @Test fun `A21 playWhenReady delegates to initialPlayer`() {
        assertTrue(buildProxy().playWhenReady)
    }

    @Test fun `A22 playerError delegates to initialPlayer`() {
        assertNull(buildProxy().playerError)
    }

    @Test fun `A23 isCommandAvailable delegates to initialPlayer`() {
        assertTrue(buildProxy().isCommandAvailable(Player.COMMAND_PLAY_PAUSE))
    }

    @Test fun `A24 isCommandAvailable switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertFalse(proxy.isCommandAvailable(Player.COMMAND_PLAY_PAUSE))
    }

    // ═════════════════════════════════════════════════════════════════════════
    // B. Queue / timeline fields
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `B01 currentMediaItem delegates to initialPlayer`() {
        assertSame(mi1, buildProxy().currentMediaItem)
    }

    @Test fun `B02 currentMediaItem switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(mi2, proxy.currentMediaItem)
    }

    @Test fun `B03 mediaItemCount delegates to initialPlayer`() {
        assertEquals(10, buildProxy().mediaItemCount)
    }

    @Test fun `B04 mediaItemCount switches to 1 after switchTo (standby has 1 item)`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(1, proxy.mediaItemCount)
    }

    @Test fun `B05 getMediaItemAt delegates to initialPlayer`() {
        assertSame(mi1, buildProxy().getMediaItemAt(7))
    }

    @Test fun `B06 getMediaItemAt switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(mi2, proxy.getMediaItemAt(0))
    }

    @Test fun `B07 nextMediaItemIndex delegates to initialPlayer`() {
        assertEquals(8, buildProxy().nextMediaItemIndex)
    }

    @Test fun `B08 nextMediaItemIndex switches to INDEX_UNSET after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(C.INDEX_UNSET, proxy.nextMediaItemIndex)
    }

    @Test fun `B09 previousMediaItemIndex delegates to initialPlayer`() {
        assertEquals(6, buildProxy().previousMediaItemIndex)
    }

    @Test fun `B10 previousMediaItemIndex switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(C.INDEX_UNSET, proxy.previousMediaItemIndex)
    }

    @Test fun `B11 hasNextMediaItem delegates to initialPlayer`() {
        assertTrue(buildProxy().hasNextMediaItem())
    }

    @Test fun `B12 hasNextMediaItem switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertFalse(proxy.hasNextMediaItem())
    }

    @Test fun `B13 hasPreviousMediaItem delegates to initialPlayer`() {
        assertTrue(buildProxy().hasPreviousMediaItem())
    }

    @Test fun `B14 hasPreviousMediaItem switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertFalse(proxy.hasPreviousMediaItem())
    }

    // ═════════════════════════════════════════════════════════════════════════
    // C. Buffer accounting and ad state
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `C01 totalBufferedDuration delegates to initialPlayer`() {
        assertEquals(47_655L, buildProxy().totalBufferedDuration)
    }

    @Test fun `C02 contentPosition delegates to initialPlayer`() {
        assertEquals(11_111L, buildProxy().contentPosition)
    }

    @Test fun `C03 contentBufferedPosition delegates to initialPlayer`() {
        assertEquals(55_555L, buildProxy().contentBufferedPosition)
    }

    @Test fun `C04 contentDuration delegates to initialPlayer`() {
        assertEquals(179_000L, buildProxy().contentDuration)
    }

    @Test fun `C05 buffer fields all switch after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(5_000L,   proxy.totalBufferedDuration)
        assertEquals(0L,       proxy.contentPosition)
        assertEquals(5_000L,   proxy.contentBufferedPosition)
        assertEquals(300_000L, proxy.contentDuration)
    }

    @Test fun `C06 isPlayingAd delegates to initialPlayer`() {
        assertFalse(buildProxy().isPlayingAd)
    }

    @Test fun `C07 currentAdGroupIndex delegates to initialPlayer`() {
        assertEquals(C.INDEX_UNSET, buildProxy().currentAdGroupIndex)
    }

    @Test fun `C08 currentAdIndexInAdGroup delegates to initialPlayer`() {
        assertEquals(C.INDEX_UNSET, buildProxy().currentAdIndexInAdGroup)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // D. Tracks and metadata
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `D01 currentTracks delegates to initialPlayer`() {
        assertSame(tracks1, buildProxy().currentTracks)
    }

    @Test fun `D02 currentTracks switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(tracks2, proxy.currentTracks)
    }

    @Test fun `D03 trackSelectionParameters delegates to initialPlayer`() {
        assertSame(tsp1, buildProxy().trackSelectionParameters)
    }

    @Test fun `D04 trackSelectionParameters switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(tsp2, proxy.trackSelectionParameters)
    }

    @Test fun `D05 mediaMetadata delegates to initialPlayer`() {
        assertSame(meta1, buildProxy().mediaMetadata)
    }

    @Test fun `D06 mediaMetadata switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(meta2, proxy.mediaMetadata)
    }

    @Test fun `D07 playlistMetadata delegates to initialPlayer`() {
        assertSame(meta1, buildProxy().playlistMetadata)
    }

    @Test fun `D08 playlistMetadata switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(meta2, proxy.playlistMetadata)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // E. Playback parameters and control flags
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `E01 playbackParameters delegates to initialPlayer`() {
        assertSame(pp1, buildProxy().playbackParameters)
    }

    @Test fun `E02 playbackParameters switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(pp2, proxy.playbackParameters)
    }

    @Test fun `E03 repeatMode delegates to initialPlayer`() {
        assertEquals(Player.REPEAT_MODE_ALL, buildProxy().repeatMode)
    }

    @Test fun `E04 repeatMode switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(Player.REPEAT_MODE_OFF, proxy.repeatMode)
    }

    @Test fun `E05 shuffleModeEnabled delegates to initialPlayer`() {
        assertTrue(buildProxy().shuffleModeEnabled)
    }

    @Test fun `E06 shuffleModeEnabled switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertFalse(proxy.shuffleModeEnabled)
    }

    @Test fun `E07 seekBackIncrement delegates to initialPlayer`() {
        assertEquals(15_000L, buildProxy().seekBackIncrement)
    }

    @Test fun `E08 seekForwardIncrement delegates to initialPlayer`() {
        assertEquals(30_000L, buildProxy().seekForwardIncrement)
    }

    @Test fun `E09 maxSeekToPreviousPosition delegates to initialPlayer`() {
        assertEquals(3_000L, buildProxy().maxSeekToPreviousPosition)
    }

    @Test fun `E10 seek increment fields all switch after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertEquals(10_000L, proxy.seekBackIncrement)
        assertEquals(10_000L, proxy.seekForwardIncrement)
        assertEquals(2_000L,  proxy.maxSeekToPreviousPosition)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // F. Commands and output
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `F01 availableCommands delegates to initialPlayer`() {
        assertSame(cmds1, buildProxy().availableCommands)
    }

    @Test fun `F02 availableCommands switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(cmds2, proxy.availableCommands)
    }

    @Test fun `F03 videoSize delegates to initialPlayer`() {
        assertSame(vs1, buildProxy().videoSize)
    }

    @Test fun `F04 videoSize switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(vs2, proxy.videoSize)
    }

    @Test fun `F05 currentCues delegates to initialPlayer`() {
        assertSame(cg1, buildProxy().currentCues)
    }

    @Test fun `F06 currentCues switches after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        assertSame(cg2, proxy.currentCues)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // G. switchTo() semantics
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `G01 switchTo same player is a no-op (no listener churn)`() {
        val proxy = buildProxy()
        val listener: Player.Listener = mock()
        proxy.addListener(listener)
        proxy.switchTo(p1)  // same player — must be a no-op
        verify(p1, never()).removeListener(listener)
    }

    @Test fun `G02 switchTo new player migrates all registered listeners`() {
        val proxy = buildProxy()
        val listener: Player.Listener = mock()
        proxy.addListener(listener)

        proxy.switchTo(p2)

        verify(p1).removeListener(listener)
        verify(p2).addListener(listener)
    }

    @Test fun `G03 switchTo migrates multiple listeners`() {
        val proxy = buildProxy()
        val l1: Player.Listener = mock()
        val l2: Player.Listener = mock()
        proxy.addListener(l1)
        proxy.addListener(l2)

        proxy.switchTo(p2)

        verify(p1).removeListener(l1)
        verify(p1).removeListener(l2)
        verify(p2).addListener(l1)
        verify(p2).addListener(l2)
    }

    @Test fun `G04 consecutive switchTo calls track the latest player`() {
        val p3: ExoPlayer = mock()
        whenever(p3.isPlaying).thenReturn(true)
        val proxy = buildProxy()

        proxy.switchTo(p2)
        assertFalse(proxy.isPlaying)   // p2: false

        proxy.switchTo(p3)
        assertTrue(proxy.isPlaying)    // p3: true
    }

    @Test fun `G05 listeners follow through multiple consecutive switchTo calls`() {
        val p3: ExoPlayer = mock()
        val proxy = buildProxy()
        val listener: Player.Listener = mock()
        proxy.addListener(listener)

        proxy.switchTo(p2)  // p1 → p2
        proxy.switchTo(p3)  // p2 → p3

        // listener must end up on p3, removed from p2
        verify(p2).removeListener(listener)
        verify(p3).addListener(listener)
    }

    @Test fun `G06 addListener registers on current player`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        val listener: Player.Listener = mock()

        proxy.addListener(listener)

        verify(p2).addListener(listener)
        verify(p1, never()).addListener(listener)
    }

    @Test fun `G07 removeListener removes from current player`() {
        val proxy = buildProxy()
        val listener: Player.Listener = mock()
        proxy.addListener(listener)
        proxy.switchTo(p2)
        verify(p2).addListener(listener)   // migrated on switch

        proxy.removeListener(listener)

        verify(p2).removeListener(listener)
    }

    @Test fun `G08 addListener does not double-register same listener instance`() {
        val proxy = buildProxy()
        val listener: Player.Listener = mock()
        proxy.addListener(listener)
        proxy.addListener(listener)  // second add of same instance

        proxy.switchTo(p2)

        // listener migrated exactly once, not twice
        verify(p1, org.mockito.kotlin.times(1)).removeListener(listener)
        verify(p2, org.mockito.kotlin.times(1)).addListener(listener)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // H. Transport command lambda delegation
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `H01 play() invokes onPlay lambda`() {
        buildProxy().play()
        assertEquals(1, playCount)
    }

    @Test fun `H02 pause() invokes onPause lambda`() {
        buildProxy().pause()
        assertEquals(1, pauseCount)
    }

    @Test fun `H03 seekToNextMediaItem() invokes onSkipNext lambda`() {
        buildProxy().seekToNextMediaItem()
        assertEquals(1, skipNextCount)
    }

    @Test fun `H04 seekToPreviousMediaItem() invokes onSkipPrev lambda`() {
        buildProxy().seekToPreviousMediaItem()
        assertEquals(1, skipPrevCount)
    }

    @Test fun `H05 transport lambdas remain correct after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        proxy.play()
        proxy.pause()
        assertEquals(1, playCount)
        assertEquals(1, pauseCount)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // I. seekTo() routing (MED-01)
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `I01 seekTo with INDEX_UNSET routes to onSeek`() {
        buildProxy().seekTo(C.INDEX_UNSET, 5_000L)
        assertEquals(5_000L, lastSeekMs)
        assertEquals(-1, lastSetTrack)
    }

    @Test fun `I02 seekTo with same index as current routes to onSeek`() {
        // p1.currentMediaItemIndex = 7
        buildProxy().seekTo(7, 5_000L)
        assertEquals(5_000L, lastSeekMs)
        assertEquals(-1, lastSetTrack)
    }

    @Test fun `I03 seekTo with different index routes to onSetTrack`() {
        // p1.currentMediaItemIndex = 7, we request index 3
        buildProxy().seekTo(3, 0L)
        assertEquals(3, lastSetTrack)
        assertEquals(-1L, lastSeekMs)
    }

    @Test fun `I04 seekTo queue jump uses _current index after switchTo`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        // p2.currentMediaItemIndex = 0
        // Index 0 is SAME as current → route to onSeek, not onSetTrack
        proxy.seekTo(0, 2_000L)
        assertEquals(2_000L, lastSeekMs)
        assertEquals(-1, lastSetTrack)
    }

    @Test fun `I05 seekTo different index after switchTo routes to onSetTrack`() {
        val proxy = buildProxy()
        proxy.switchTo(p2)
        // p2.currentMediaItemIndex = 0
        // Index 2 differs → queue jump
        proxy.seekTo(2, 0L)
        assertEquals(2, lastSetTrack)
        assertEquals(-1L, lastSeekMs)
    }
}
