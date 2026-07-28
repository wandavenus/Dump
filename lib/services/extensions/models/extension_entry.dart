class ExtensionEntry {
  const ExtensionEntry({
    required this.id,
    required this.name,
    required this.author,
    required this.version,
    required this.description,
    required this.type,
    required this.packageUrl,
    this.iconUrl,
    String? displayName,
  }) : displayName = displayName ?? name;
  final String displayName;
  final String id, name, author, version, description, type, packageUrl;
  final String? iconUrl;
  factory ExtensionEntry.fromJson(Map<String, dynamic> json) => ExtensionEntry(
    id: (json['id'] ?? json['extensionId'] ?? json['name'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    displayName:
        (json['display_name'] ?? json['displayName'] ?? json['name'] ?? '')
            .toString(),
    author: (json['author'] ?? '').toString(),
    version: (json['version'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
    type: _typeFromJson(json),
    packageUrl: (json['packageUrl'] ?? json['downloadUrl'] ?? json['url'] ?? '')
        .toString(),
    iconUrl: (json['icon'] ?? json['iconUrl'])?.toString(),
  );
}

String _typeFromJson(Map<String, dynamic> json) {
  final value = json['type'] ?? json['supportedType'] ?? json['category'];
  if (value is List && value.isNotEmpty) return value.first.toString();
  final raw = (value ?? 'metadata_provider').toString();
  if (raw == 'download') return 'download_provider';
  if (raw == 'metadata') return 'metadata_provider';
  if (raw == 'lyrics') return 'lyrics_provider';
  return raw;
}
