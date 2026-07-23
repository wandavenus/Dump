/// Lifecycle / health status of a [NativeModule].
enum NativeModuleStatus {
  /// [NativeModule.initialize] has not been called yet.
  uninitialized,

  /// [NativeModule.initialize] completed and [NativeModule.isAvailable] is true.
  available,

  /// [NativeModule.initialize] completed but the module is not available
  /// on this device (missing hardware, unsupported API level, etc.).
  unavailable,

  /// [NativeModule.initialize] threw an exception.
  error,

  /// [NativeModule.dispose] has been called.
  disposed,
}
