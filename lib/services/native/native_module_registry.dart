import 'contracts/native_module.dart';
import '../log_service.dart';
import '../boot_trace.dart';

/// Central registry for all [NativeModule] instances.
///
/// [PlaybackManager] owns the registry lifecycle — it registers modules and
/// calls [initializeAll] / [disposeAll].  No other class should call these.
///
/// All other services query capabilities through [PlaybackManager], never
/// directly through this registry.
///
/// ## Adding a new native module
///
/// 1. Implement [NativeModule] (see `contracts/native_module.dart`).
/// 2. Register the singleton instance in `PlaybackManager.initialize()`:
///    ```dart
///    NativeModuleRegistry.register(MyNewBridge.instance);
///    ```
/// 3. Expose any required API on [PlaybackManager] — not on the bridge itself.
///
/// That's all.  No changes to existing modules or to the registry itself.
class NativeModuleRegistry {
  NativeModuleRegistry._();

  static final List<NativeModule> _modules = [];

  /// Register a module.  Must be called before [initializeAll].
  static void register(NativeModule module) {
    assert(
      !_modules.any((m) => m.moduleId == module.moduleId),
      'Duplicate moduleId "${module.moduleId}" — each module must be registered once.',
    );
    _modules.add(module);
  }

  /// Initialize all registered modules in registration order.
  static Future<void> initializeAll() async {
    BootTrace.log('ENTER NativeModuleRegistry.initializeAll() '
        '(${_modules.length} module(s): ${_modules.map((m) => m.moduleId).join(', ')})');
    for (final m in _modules) {
      BootTrace.log('BEFORE await ${m.moduleId}.initialize()');
      final sw = Stopwatch()..start();
      try {
        await m.initialize();
        BootTrace.log(
            'AFTER  await ${m.moduleId}.initialize() (${sw.elapsedMilliseconds}ms)');
        LogService.log(
          'NativeModuleRegistry',
          '${m.displayName} (${m.moduleId}) — '
          '${m.isAvailable ? 'available' : 'unavailable (stub)'}',
        );
      } catch (e, st) {
        BootTrace.log(
            'EXCEPTION in ${m.moduleId}.initialize() after '
            '${sw.elapsedMilliseconds}ms: $e\n$st');
        LogService.log(
          'NativeModuleRegistry',
          '${m.displayName} init error: $e',
        );
      }
    }
    BootTrace.log('EXIT  NativeModuleRegistry.initializeAll()');
  }

  /// Dispose all registered modules in reverse registration order.
  static Future<void> disposeAll() async {
    for (final m in _modules.reversed) {
      try {
        await m.dispose();
      } catch (_) {
        // Suppress disposal errors — app is shutting down.
      }
    }
    _modules.clear();
  }

  /// Snapshot of all registered modules (unmodifiable).
  static List<NativeModule> get all => List.unmodifiable(_modules);

  /// Aggregate capabilities from every registered module.
  ///
  /// Returns a map of `moduleId → capabilities`.
  static Future<Map<String, List<NativeCapability>>> queryAllCapabilities() async {
    final result = <String, List<NativeCapability>>{};
    for (final m in _modules) {
      try {
        result[m.moduleId] = await m.queryCapabilities();
      } catch (e) {
        result[m.moduleId] = [
          NativeCapability(key: 'error', supported: false, version: e.toString()),
        ];
      }
    }
    return result;
  }
}
