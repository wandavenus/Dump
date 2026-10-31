package dev.wndavenz.music.automix

/**
 * Interim AutoMix decision contract. These are hand-tuned gates, not
 * calibrated probabilities; the native header
 * `native_audio_runtime/src/automix_native.h` is the source of truth and the
 * Dart mirror lives in `lib/services/automix_service/contract.dart`.
 */
internal object AutomixContract {
    const val BPM_MIN = 50f
    const val BPM_MAX = 220f

    const val TEMPO_CONFIDENCE_MIN = 0.35f
    const val KEY_CONFIDENCE_MIN = 0.55f
    const val STRUCTURE_CONFIDENCE_MIN = 0.65f
    const val DROP_CONFIDENCE_MIN = 0.55f
    const val DROP_HANDOVER_MIN_MS = 8_000L
    const val DROP_HANDOVER_MAX_MS = 150_000L
    const val VOCAL_CONFIDENCE_MIN = 0.45f
    const val VOCAL_LIKELIHOOD_MIN = 0.55f

    const val FADE_MIN_SECONDS = 1.5f
    const val FADE_MAX_SECONDS = 12f

    val SUPPORTED_METERS = setOf(2, 3, 4, 6)
}
