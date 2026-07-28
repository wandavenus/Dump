/// Rate limiter per-provider.
///
/// Jika provider mengembalikan HTTP 429 / rate-limit,
/// panggil [markRateLimited(provider)] untuk memberi cooldown otomatis.
class ProviderRateLimiter {
  static final ProviderRateLimiter instance = ProviderRateLimiter._();
  ProviderRateLimiter._();

  // (Stopwatch running since markRateLimited, cooldown duration).
  // Stopwatch.elapsed is monotonic — immune to wall-clock adjustments.
  final Map<String, (Stopwatch, Duration)> _cooldowns = {};

  /// True jika provider sedang dalam masa cooldown.
  bool isLimited(String providerName) {
    final entry = _cooldowns[providerName];
    if (entry == null) return false;
    final (sw, duration) = entry;
    if (sw.elapsed >= duration) {
      _cooldowns.remove(providerName);
      return false;
    }
    return true;
  }

  /// Tandai provider kena rate limit — cooldown [duration] (default 60 detik).
  void markRateLimited(
    String providerName, {
    Duration duration = const Duration(seconds: 60),
  }) {
    _cooldowns[providerName] = (Stopwatch()..start(), duration);
  }

  /// Reset cooldown untuk provider tertentu.
  void reset(String providerName) => _cooldowns.remove(providerName);

  /// Reset semua cooldown.
  void resetAll() => _cooldowns.clear();
}
