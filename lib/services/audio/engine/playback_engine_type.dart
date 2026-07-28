enum PlaybackEngineType {
  media3('media3', 'Media3'),
  aaudio('aaudio', 'AAudio (low latency)');

  const PlaybackEngineType(this.id, this.label);

  final String id;
  final String label;

  static PlaybackEngineType fromId(String? id) => values.firstWhere(
    (type) => type.id == id,
    orElse: () => PlaybackEngineType.media3,
  );
}
