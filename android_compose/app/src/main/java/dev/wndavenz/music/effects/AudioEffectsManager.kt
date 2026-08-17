package dev.wndavenz.music.effects

import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import android.os.Handler
import dev.wndavenz.music.diagnostics.CrossfadeTimelineLogger
import dev.wndavenz.music.events.NativeLogger

/**
 * Manages Android audio effects lifecycle (EQ, LoudnessEnhancer, BassBoost).
 *
 * Improvements for Android 11 / MIUI 12:
 *
 * RC-03 (already fixed): attachEffects() retry guard checks lastAttachedSessionId
 *   at the start of every retry attempt so a stale delayed retry doesn't override
 *   a newer session attachment.
 *
 * RC-04 (already fixed): equalizerParameters() never creates a temp Equalizer on
 *   the main thread; returns safe defaults when EQ is not yet attached.
 *
 * MIUI 12 specific:
 *   - Retry delays tripled (150 ms → 400 ms → 900 ms): MIUI's AudioFlinger
 *     sometimes takes longer than stock Android to publish a new audio session.
 *   - isEffectTypeAvailable() falls back to a try-instantiation probe when
 *     queryEffects() returns null/empty (observed on some MIUI 12 devices).
 *   - Effect init errors are individually silenced; a failing effect never
 *     blocks the remaining effects from loading.
 *   - setTargetGain() receives the gain as an Int (the signature that compiles
 *     on all API levels without needing a double cast).
 *
 * Crossfade note:
 *   attachEffects() is also called explicitly after crossfade completes (from the
 *   service's onCrossfadeComplete callback) to re-attach all effects to the newly
 *   active player's audio session.  The lastAttachedSessionId guard prevents
 *   a no-op double-attach if the session ID didn't change.
 */
class AudioEffectsManager(private val effectHandler: Handler) {

    private var equalizer:   Equalizer?         = null
    private var loudness:    LoudnessEnhancer?   = null
    private var bassBoost:   BassBoost?          = null

    private var lastAttachedSessionId = AudioEffect.ERROR_BAD_VALUE

    // K7 fix: monotonically increasing generation counter. Every fresh
    // attachEffects() request (attempt 0) bumps it; each delayed retry captures
    // the generation it was scheduled under and bails out if a newer request
    // bumped it in the meantime. Without this, a retry scheduled against an
    // OLD session could fire after the active session changed (device output
    // change → resetAndReattach, crossfade promotion, bit-perfect toggle) and
    // releaseEffects() the NEW session's effects only to rebuild them against
    // the old, dead audio session — leaving EQ/bass/loudness attached to a
    // session nothing plays into.
    private var attachGeneration = 0L

    // ── Persisted intent state ────────────────────────────────────────────────
    var eqEnabled:            Boolean = false;  private set
    var loudnessEnabled:      Boolean = false;  private set
    var loudnessTargetMb:     Float   = 0f;     private set
    var bassBoostEnabled:     Boolean = false;  private set
    var bassBoostStrength:    Short   = 0;      private set
    val bandGains = mutableMapOf<Short, Short>()

    // ── Capability flags ──────────────────────────────────────────────────────
    var bassBoostSupported:   Boolean = false;  private set

    // ── Session attachment ────────────────────────────────────────────────────

    /**
     * Attach all enabled effects to the given audio session.
     *
     * Safe to call from any thread — all work runs on effectHandler (main looper).
     * If called multiple times with the same sessionId (e.g., after crossfade where
     * the active player's session didn't change), the lastAttachedSessionId guard
     * makes the call a no-op.
     *
     * @param attempt retry counter; retries use exponential-ish backoff:
     *   attempt 0 → immediate
     *   attempt 1 → 150 ms delay
     *   attempt 2 → 400 ms delay
     *   attempt 3 → 900 ms delay (final)
     */
    fun attachEffects(sessionId: Int, attempt: Int = 0, expectedGeneration: Long = -1L) {
        // Ignore invalid or default session IDs
        if (sessionId <= 0 || sessionId == AudioEffect.ERROR_BAD_VALUE) return
        // K7 fix: a retry only runs if no newer attach request (to any session)
        // was made since it was scheduled. Checked before the RC-03 guard so a
        // stale retry can never tear down / re-attach a newer session.
        if (attempt > 0) {
            if (expectedGeneration != attachGeneration) {
                log("verbose", "attachEffects retry dropped — superseded by a newer attach request")
                return
            }
        } else {
            // Fresh request — any pending retries from older requests are stale.
            attachGeneration++
        }
        // RC-03: guard checked at every retry entry
        if (sessionId == lastAttachedSessionId) {
            log("verbose", "attachEffects skipped — already attached to session=$sessionId")
            CrossfadeTimelineLogger.stamp(
                "attachEffects: SKIPPED (already on session=$sessionId lastAttached=$lastAttachedSessionId)")
            return
        }

        // ── Dropout investigation stamp ────────────────────────────────────────
        // releaseEffects() calls .release() on Equalizer, LoudnessEnhancer, etc.
        // On some MIUI/Android versions releasing an AudioEffect object that is
        // still attached to an active AudioFlinger session causes a brief pipeline
        // flush.  We stamp before AND after to measure the cost.
        CrossfadeTimelineLogger.stamp(
            "attachEffects: ENTER session=$sessionId attempt=$attempt" +
            " lastAttached=$lastAttachedSessionId" +
            " eq=${equalizer != null} loud=${loudness != null}")

        releaseEffects()
        CrossfadeTimelineLogger.stamp(
            "attachEffects: releaseEffects() DONE — old effects torn down session=$sessionId")

        var anyOk = false
        // Tracked separately from anyOk: previously a single successfully-attached
        // effect (e.g. LoudnessEnhancer) suppressed the retry-on-failure path below
        // even when the Equalizer itself failed to attach — leaving `equalizer` null
        // permanently for that session. Band-gain/enable calls against a null
        // `equalizer` are silent no-ops (see setEqualizerBandGain/setEqualizerEnabled),
        // so a failed EQ attach here surfaced to the user as "slider moves, dB
        // updates, but zero audible/native effect" with no error anywhere.
        var eqOk = false

        // ── Equalizer ─────────────────────────────────────────────────────────
        CrossfadeTimelineLogger.stamp("attachEffects: Equalizer(0,$sessionId) START")
        try {
            equalizer = Equalizer(0, sessionId).also { eq ->
                eq.enabled = eqEnabled
                bandGains.forEach { (b, g) ->
                    eq.setBandLevel(b, g.coerceIn(eq.bandLevelRange[0], eq.bandLevelRange[1]))
                }
                anyOk = true
                eqOk = true
            }
            CrossfadeTimelineLogger.stamp("attachEffects: Equalizer ATTACHED session=$sessionId")
        } catch (e: Exception) {
            log("warn", "Equalizer init failed (session=$sessionId a${attempt+1}): ${e.message}")
            CrossfadeTimelineLogger.stamp("attachEffects: Equalizer FAILED: ${e.message}")
        }

        // ── LoudnessEnhancer ──────────────────────────────────────────────────
        CrossfadeTimelineLogger.stamp("attachEffects: LoudnessEnhancer($sessionId) START")
        try {
            loudness = LoudnessEnhancer(sessionId).also { le ->
                le.setTargetGain(loudnessTargetMb.toInt())
                le.enabled = loudnessEnabled
                anyOk = true
            }
            CrossfadeTimelineLogger.stamp("attachEffects: LoudnessEnhancer ATTACHED session=$sessionId")
        } catch (e: Exception) {
            log("warn", "LoudnessEnhancer init failed (session=$sessionId a${attempt+1}): ${e.message}")
            CrossfadeTimelineLogger.stamp("attachEffects: LoudnessEnhancer FAILED: ${e.message}")
        }

        // ── BassBoost ─────────────────────────────────────────────────────────
        bassBoostSupported = false
        if (isEffectTypeAvailable(AudioEffect.EFFECT_TYPE_BASS_BOOST)) {
            CrossfadeTimelineLogger.stamp("attachEffects: BassBoost($sessionId) START")
            try {
                bassBoost = BassBoost(0, sessionId).also { bb ->
                    bb.setStrength(bassBoostStrength)
                    bb.enabled = bassBoostEnabled
                    bassBoostSupported = true
                }
                CrossfadeTimelineLogger.stamp("attachEffects: BassBoost ATTACHED session=$sessionId")
            } catch (e: Exception) {
                log("warn", "BassBoost init failed (a${attempt+1}): ${e.message}")
                CrossfadeTimelineLogger.stamp("attachEffects: BassBoost FAILED: ${e.message}")
            }
        }

        // A session is only considered fully settled once the Equalizer attached —
        // not merely "some effect attached" (anyOk). Retrying on !eqOk (rather than
        // !anyOk) is what actually fixes the "EQ slider does nothing" bug: without
        // this, a session where e.g. LoudnessEnhancer attached but Equalizer's
        // AudioEffect() constructor threw (transient MIUI AudioFlinger race) would
        // lock in lastAttachedSessionId here and never retry — every future
        // setEqualizerBandGain() call would then be a permanent, silent no-op for
        // the rest of that track (see setEqualizerBandGain's null-equalizer guard).
        if (anyOk && eqOk) {
            lastAttachedSessionId = sessionId
            log("info", "attachEffects OK session=$sessionId a${attempt+1} " +
                "bass=$bassBoostSupported")
            CrossfadeTimelineLogger.stamp(
                "attachEffects: ALL DONE OK session=$sessionId" +
                " bass=$bassBoostSupported")
            return
        }

        // Equalizer (and/or everything else) not attached yet — schedule retry.
        if (attempt < 3) {
            val delayMs = when (attempt) {
                0 -> 150L   // first retry after 150 ms
                1 -> 400L   // second retry
                else -> 900L // final retry (MIUI 12 can be slow)
            }
            log("warn", "attachEffects session=$sessionId eq=$eqOk any=$anyOk, retry in ${delayMs}ms")
            // K7 fix: pin the retry to the generation it belongs to so a stale
            // delayed retry is dropped if a newer attach supersedes it.
            val genAtSchedule = attachGeneration
            effectHandler.postDelayed(
                { attachEffects(sessionId, attempt + 1, genAtSchedule) },
                delayMs,
            )
        } else if (anyOk) {
            // Retries exhausted but at least one effect (not EQ) is live — accept
            // this as the final state so lastAttachedSessionId still guards future
            // duplicate attaches, but make the permanent EQ gap loud in the logs.
            lastAttachedSessionId = sessionId
            log("warn", "attachEffects session=$sessionId gave up after ${attempt+1} attempts — " +
                "Equalizer never attached, EQ controls will be silent no-ops until next session change")
            CrossfadeTimelineLogger.stamp(
                "attachEffects: GAVE UP on Equalizer, session=$sessionId settled without EQ")
        } else {
            log("warn", "attachEffects session=$sessionId failed after ${attempt+1} attempts")
        }
    }

    fun releaseEffects() {
        try { equalizer?.release()   } catch (_: Exception) {}
        try { loudness?.release()    } catch (_: Exception) {}
        try { bassBoost?.release()   } catch (_: Exception) {}
        equalizer   = null
        loudness    = null
        bassBoost   = null
        // Do NOT reset lastAttachedSessionId here — it guards attachEffects retries.
        // It is reset in the guard at the top of attachEffects when a new session arrives.
    }

    /**
     * Force-reattach all effects to [sessionId], bypassing the
     * [lastAttachedSessionId] guard.
     *
     * Used by [AudioCapabilitiesReceiver] after an audio-output-device change
     * (BT connect/disconnect, HDMI) where MIUI 12 can invalidate the effect
     * chain on the existing AudioSession without changing its numeric ID.
     * Resetting [lastAttachedSessionId] ensures [attachEffects] runs through
     * the full init sequence rather than treating it as a no-op.
     */
    fun resetAndReattach(sessionId: Int) {
        lastAttachedSessionId = AudioEffect.ERROR_BAD_VALUE
        attachEffects(sessionId)
        log("info", "resetAndReattach: forced re-attach to session=$sessionId")
    }

    // ── Effect setters ────────────────────────────────────────────────────────

    fun setEqualizerEnabled(enabled: Boolean) {
        eqEnabled = enabled
        val eq = equalizer
        if (eq == null) {
            log("warn", "setEqualizerEnabled($enabled): equalizer not attached — " +
                "state saved, no native effect to apply it to (session=$lastAttachedSessionId)")
            return
        }
        try { eq.enabled = enabled } catch (e: Exception) {
            log("warn", "setEqualizerEnabled($enabled) failed: ${e.message}")
        }
    }

    fun setEqualizerBandGain(band: Short, gainHundredths: Short) {
        bandGains[band] = gainHundredths
        val eq = equalizer
        if (eq == null) {
            // Previously a fully silent no-op — the UI slider would move and
            // persist the value with zero indication that nothing reached the
            // audio path. Logged so this is visible via the in-app Log Viewer.
            log("warn", "setEqualizerBandGain(band=$band): equalizer not attached — " +
                "gain saved but not applied (session=$lastAttachedSessionId)")
            return
        }
        try {
            eq.setBandLevel(band, gainHundredths.coerceIn(
                eq.bandLevelRange[0], eq.bandLevelRange[1]))
        } catch (e: Exception) {
            log("warn", "setEqualizerBandGain(band=$band) failed: ${e.message}")
        }
    }

    fun setLoudnessTargetGain(gainMb: Float) {
        loudnessTargetMb = gainMb
        try { loudness?.setTargetGain(gainMb.toInt()) } catch (_: Exception) {}
    }

    fun setLoudnessEnabled(enabled: Boolean) {
        loudnessEnabled = enabled
        try { loudness?.enabled = enabled } catch (_: Exception) {}
    }

    fun setBassBoostEnabled(enabled: Boolean) {
        bassBoostEnabled = enabled
        try { bassBoost?.enabled = enabled } catch (_: Exception) {}
    }

    fun setBassBoostStrength(strength: Short) {
        bassBoostStrength = strength
        try { bassBoost?.setStrength(strength) } catch (_: Exception) {}
        if (bassBoostEnabled != (strength > 0)) setBassBoostEnabled(strength > 0)
    }

    // ── Queries ───────────────────────────────────────────────────────────────

    /** RC-04 fix: returns safe defaults when EQ is not attached. */
    fun equalizerParameters(): Map<String, Any> {
        return try {
            val eq = equalizer ?: return defaultEqualizerParameters()
            val numBands = eq.numberOfBands.toInt()
            mapOf(
                "minDecibels" to eq.bandLevelRange[0] / 100.0,
                "maxDecibels" to eq.bandLevelRange[1] / 100.0,
                "bands"       to List(numBands) { it },
                // getCenterFreq() returns millihertz — divide by 1000 to get Hz.
                // This is the actual hardware-reported center frequency for each band,
                // which varies by device and Android version.
                "frequencies" to List(numBands) { b ->
                    eq.getCenterFreq(b.toShort()) / 1000
                }
            )
        } catch (_: Exception) { defaultEqualizerParameters() }
    }

    fun effectSupportMap() = mapOf(
        "bassBoostSupported"   to bassBoostSupported,
        "equalizerAttached"    to (equalizer != null),
        "loudnessAttached"     to (loudness  != null),
    )

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun defaultEqualizerParameters() = mapOf(
        "minDecibels" to -15.0,
        "maxDecibels" to  15.0,
        "bands"       to listOf(0, 1, 2, 3, 4),
        // Typical 5-band center frequencies for the stock Android Equalizer.
        // Used as fallback when the EQ is not yet attached to an audio session.
        "frequencies" to listOf(60, 230, 910, 3600, 14000)
    )

    /**
     * Checks whether an effect type is available on this device.
     *
     * MIUI 12 fallback: if queryEffects() returns null or empty (seen on some
     * Xiaomi builds), we try to instantiate the effect directly.  A successful
     * instantiation means the type is supported; we release it immediately.
     */
    private fun isEffectTypeAvailable(type: java.util.UUID): Boolean {
        // queryEffects() requires API 21
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val descriptors = AudioEffect.queryEffects()
                if (!descriptors.isNullOrEmpty()) {
                    return descriptors.any { it.type == type }
                }
                // queryEffects returned empty — fall through to probe below
            } catch (_: Exception) { /* fall through */ }
        }

        // LOW-03 fix: The original probe used sessionId=0 (the global audio session), which
        // attaches a live effect to every audio track on the device — a serious side-effect.
        // We now return false when queryEffects() is unavailable/empty; callers treat an
        // unavailable report as "disable gracefully" which is the correct safe behaviour.
        return false
    }

    private fun log(level: String, msg: String) = NativeLogger.emit(level, "Effects", msg)
}
