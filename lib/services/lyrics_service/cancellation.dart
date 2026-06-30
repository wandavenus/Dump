import 'dart:async';

/// Token pembatalan yang digunakan oleh semua provider untuk
/// membatalkan request HTTP saat pengguna ganti lagu.
///
/// Pola pemakaian:
/// ```dart
/// final token = CancellationToken();
/// // ... kirim ke semua provider ...
/// token.cancel(); // batalkan semua request
/// ```
class CancellationToken {
  bool _cancelled = false;
  final List<void Function()> _callbacks = [];

  bool get isCancelled => _cancelled;

  /// Tambah callback yang dipanggil saat token dibatalkan.
  void onCancel(void Function() cb) {
    if (_cancelled) {
      cb();
    } else {
      _callbacks.add(cb);
    }
  }

  /// Batalkan token — memanggil semua callback terdaftar.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final cb in _callbacks) {
      try {
        cb();
      } catch (_) {}
    }
    _callbacks.clear();
  }

  /// Lempar [CancelledException] jika token sudah dibatalkan.
  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }

  /// Wrap sebuah Future agar otomatis dibatalkan jika token dibatalkan.
  Future<T> guardFuture<T>(Future<T> future) {
    if (_cancelled) return Future.error(const CancelledException());
    final completer = Completer<T>();
    future
        .then((v) {
          if (!completer.isCompleted) completer.complete(v);
        })
        .catchError((e) {
          if (!completer.isCompleted) completer.completeError(e);
        });
    onCancel(() {
      if (!completer.isCompleted) {
        completer.completeError(const CancelledException());
      }
    });
    return completer.future;
  }
}

class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => 'CancelledException';
}
