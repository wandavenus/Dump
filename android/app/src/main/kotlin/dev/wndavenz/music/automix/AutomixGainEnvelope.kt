package dev.wndavenz.music.automix

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * Production equal-power deck envelope shared by CrossfadeController and JVM tests.
 *
 * The target volume is supplied on every fade tick, so user volume changes and
 * audio-focus ducking are reflected without restarting the transition.
 */
internal object AutomixGainEnvelope {
    data class Gains(val outgoing: Float, val incoming: Float)

    fun gains(
        progress: Float,
        targetVolume: Float,
        curveGamma: Float,
        outgoingTrim: Float,
        incomingTrim: Float,
    ): Gains {
        val t = progress.takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: 0f
        val target = targetVolume.takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: 0f
        val gamma = curveGamma.takeIf { it.isFinite() }?.coerceIn(0.6f, 1.6f) ?: 1f
        val outTrim = outgoingTrim.takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: 1f
        val inTrim = incomingTrim.takeIf { it.isFinite() }?.coerceIn(0f, 1f) ?: 1f

        // gamma > 1 accelerates handover (incoming rises faster, outgoing drops faster);
        // gamma < 1 decelerates handover (longer overlap blend).
        val shaped = if (gamma == 1f) t else t.toDouble().pow(1.0 / gamma.toDouble()).toFloat()
        val attack = if (t >= 0.25f) 1f else t / 0.25f
        val outgoingTrimNow = 1f - (1f - outTrim) * attack
        val release = if (t <= 0.75f) 0f else (t - 0.75f) / 0.25f
        val incomingTrimNow = inTrim + (1f - inTrim) * release
        val theta = (shaped * PI / 2.0).toFloat()
        val outgoingGain = outgoingTrimNow * cos(theta)
        val incomingGain = incomingTrimNow * sin(theta)
        return Gains(
            outgoing = (target * outgoingGain).coerceIn(0f, target),
            incoming = (target * incomingGain).coerceIn(0f, target),
        )
    }
}
