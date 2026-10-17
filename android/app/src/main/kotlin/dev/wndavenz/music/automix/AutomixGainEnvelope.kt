package dev.wndavenz.music.automix

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * Production equal-power deck envelope shared by CrossfadeController and JVM tests.
 *
 * The target volume is supplied on every fade tick, so user volume changes and
 * audio-focus ducking are reflected without restarting the transition. A shared
 * L1 gain budget bounds the sum of the two deck gains for correlated material.
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

        val shaped = if (gamma == 1f) t else t.toDouble().pow(gamma.toDouble()).toFloat()
        val attack = if (t >= 0.25f) 1f else t / 0.25f
        val outgoingTrimNow = 1f - (1f - outTrim) * attack
        val release = if (t <= 0.75f) 0f else (t - 0.75f) / 0.25f
        val incomingTrimNow = inTrim + (1f - inTrim) * release
        val theta = (shaped * PI / 2.0).toFloat()
        val outgoingGain = outgoingTrimNow * cos(theta)
        val incomingGain = incomingTrimNow * sin(theta)
        val gainSum = outgoingGain + incomingGain
        val headroomScale = if (gainSum > 1f) 1f / gainSum else 1f

        return Gains(
            outgoing = (target * outgoingGain * headroomScale).coerceIn(0f, target),
            incoming = (target * incomingGain * headroomScale).coerceIn(0f, target),
        )
    }
}
