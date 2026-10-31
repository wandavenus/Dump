part of '../automix_service.dart';

/// Interim AutoMix decision contract.
///
/// These are hand-tuned gates, not calibrated probabilities (audit AM9-M08).
/// The native header `native_audio_runtime/src/automix_native.h` is the source
/// of truth; the contract tests keep this mirror and the Kotlin mirror in
/// `AutomixContract.kt` aligned with it.
abstract final class AutomixContract {
  static const double bpmMin = 50.0;
  static const double bpmMax = 220.0;

  static const double tempoConfidenceMin = 0.35;
  static const double keyConfidenceMin = 0.55;
  static const double structureConfidenceMin = 0.65;
  static const double dropConfidenceMin = 0.55;

  /// Early handover may seek to an incoming drop between these bounds. The
  /// upper bound is deliberately longer than the 65 s outgoing lead window:
  /// the seek is to the incoming track's first drop, not to the outgoing EOF.
  static const int dropHandoverMinMs = 8000;
  static const int dropHandoverMaxMs = 150000;
  static const double vocalConfidenceMin = 0.45;
  static const double vocalLikelihoodMin = 0.55;

  static const double fadeMinSeconds = 1.5;
  static const double fadeMaxSeconds = 12.0;

  static const Set<int> supportedMeters = {2, 3, 4, 6};
}
