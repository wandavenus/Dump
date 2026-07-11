import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:leak_tracker/leak_tracker.dart';

import 'log_service.dart';

/// Integrates [LeakTracking] (package:leak_tracker) dengan [LogService].
///
/// - Hanya aktif di **debug build** ([kDebugMode] == true).
/// - On/off mengikuti [LogService.loggingEnabled] — saat logging diaktifkan
///   leak tracking ikut mulai; saat logging dimatikan, leak tracking berhenti
///   dan laporan akhir dikirim ke LogService.
/// - Setiap 60 detik (saat aktif) laporan leak otomatis dikirim.
/// - Panggil [checkNow] dari Debug Section untuk cek manual kapan saja.
class LeakTrackerService {
  LeakTrackerService._();

  static const String _cat = 'LeakTracker';
  static const Duration _checkInterval = Duration(seconds: 60);

  static Timer? _timer;
  static VoidCallback? _loggingListener;
  static bool _isHooked = false;

  // ── Init / Dispose ───────────────────────────────────────────────────────

  /// Panggil sekali dari [main()] setelah [LogService.init()] selesai.
  static void init() {
    if (!kDebugMode) return;
    _loggingListener = _onLoggingToggled;
    LogService.loggingEnabled.addListener(_loggingListener!);
    // Terapkan state saat ini langsung.
    _applyState(LogService.loggingEnabled.value);
  }

  /// Panggil saat app shutdown untuk membersihkan listener.
  static void dispose() {
    if (!kDebugMode) return;
    if (_loggingListener != null) {
      LogService.loggingEnabled.removeListener(_loggingListener!);
      _loggingListener = null;
    }
    _stop(isDispose: true);
  }

  // ── Toggle listener ──────────────────────────────────────────────────────

  static void _onLoggingToggled() =>
      _applyState(LogService.loggingEnabled.value);

  static void _applyState(bool enabled) {
    if (!kDebugMode) return;
    if (enabled) {
      _start();
    } else {
      _stop();
    }
  }

  // ── Start ────────────────────────────────────────────────────────────────

  static void _start() {
    if (LeakTracking.isStarted) return;
    try {
      LeakTracking.start(config: LeakTrackingConfig.passive());

      if (!_isHooked) {
        FlutterMemoryAllocations.instance.addListener(_onAllocationEvent);
        _isHooked = true;
      }

      _timer?.cancel();
      _timer = Timer.periodic(_checkInterval, (_) => _collectAndReport());

      LogService.log(_cat, 'Leak tracking dimulai (auto-check setiap 60 s)');
    } catch (e, st) {
      LogService.warn(_cat, 'Gagal start: $e\n$st');
    }
  }

  // ── Stop ─────────────────────────────────────────────────────────────────

  static void _stop({bool isDispose = false}) {
    _timer?.cancel();
    _timer = null;

    if (_isHooked) {
      FlutterMemoryAllocations.instance.removeListener(_onAllocationEvent);
      _isHooked = false;
    }

    if (!LeakTracking.isStarted) return;

    // Kumpulkan laporan akhir, lalu stop.
    _collectAndReport(label: isDispose ? 'shutdown' : 'final').then((_) {
      try {
        LeakTracking.stop();
      } catch (_) {}
      // Log ini bisa tidak muncul kalau loggingEnabled sudah false —
      // itu wajar; user sudah minta logging dimatikan.
      LogService.log(_cat, 'Leak tracking dihentikan');
    });
  }

  // ── Allocation hook ──────────────────────────────────────────────────────

  static void _onAllocationEvent(ObjectEvent event) {
    if (LeakTracking.isStarted) {
      LeakTracking.dispatchObjectEvent(event.toMap());
    }
  }

  // ── Collect & report ─────────────────────────────────────────────────────

  static Future<void> _collectAndReport({String? label}) async {
    if (!LeakTracking.isStarted) return;
    try {
      // Tandai semua objek yang belum di-dispose sebagai leak sebelum collect.
      if (label != null) {
        LeakTracking.declareNotDisposedObjectsAsLeaks();
      }

      final leaks = await LeakTracking.collectLeaks();

      final tag = label != null ? '[$label] ' : '';

      if (leaks.total == 0) {
        if (label != null) {
          LogService.log(_cat, '${tag}Tidak ada leak terdeteksi');
        }
        return;
      }

      LogService.warn(
        _cat,
        '$tag${leaks.total} leak: '
        '${leaks.notDisposed.length} not-disposed, '
        '${leaks.notGCed.length} not-GCed',
      );

      for (final r in leaks.notDisposed) {
        LogService.warn(_cat, '[NOT DISPOSED] ${r.type}');
      }
      for (final r in leaks.notGCed) {
        LogService.error(_cat, '[NOT GCed] ${r.type}');
      }
    } catch (e) {
      LogService.warn(_cat, 'collectLeaks gagal: $e');
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Picu pengecekan leak manual — bisa dipanggil dari Debug Section.
  /// No-op kalau leak tracking tidak aktif atau bukan debug build.
  static Future<void> checkNow() async {
    if (!kDebugMode || !LeakTracking.isStarted) return;
    await _collectAndReport(label: 'manual');
  }

  /// True kalau leak tracking sedang berjalan.
  static bool get isRunning => kDebugMode && LeakTracking.isStarted;
}
