class ExtensionRuntimeException implements Exception {
  const ExtensionRuntimeException(this.extensionId, this.phase, this.message);

  final String extensionId;
  final String phase;
  final String message;

  @override
  String toString() => 'Extension $extensionId $phase failed: $message';
}
