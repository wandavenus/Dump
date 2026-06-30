/// Rate limiter per-provider.
///
/// Jika provider mengembalikan HTTP 429 / rate-limit,
/// panggil [markRateLimited(provider)] untuk memberi cooldown otomatis.
class ProviderRateLimiter {
  static final ProviderRateLimiter instance = ProviderRateLimiter._();
  ProviderRateLimiter._();

  final Map<String, DateTime> _cooldownUntil = {};

  /// True jika provider sedang dalam masa cooldown.
  bool isLimited(String providerName) {
    final until = _cooldownUntil[providerName];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _cooldownUntil.remove(providerName);
      return false;
    }
    return true;
  }

  /// Tandai provider kena rate limit — cooldown [duration] (default 60 detik).
  void markRateLimited(
    String providerName, {
    Duration duration = const Duration(seconds: 60),
  }) {
    _cooldownUntil[providerName] = DateTime.now().add(duration);
  }

  /// Reset cooldown untuk provider tertentu.
  void reset(String providerName) => _cooldownUntil.remove(providerName);

  /// Reset semua cooldown.
  void resetAll() => _cooldownUntil.clear();
}
