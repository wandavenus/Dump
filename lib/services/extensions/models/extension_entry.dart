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
  });
  final String id, name, author, version, description, type, packageUrl;
  final String? iconUrl;
  factory ExtensionEntry.fromJson(Map<String, dynamic> json) => ExtensionEntry(
    id: (json['id'] ?? json['extensionId'] ?? json['name'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    author: (json['author'] ?? '').toString(),
    version: (json['version'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
    type: (json['type'] ?? json['supportedType'] ?? json['category'] ?? 'music')
        .toString(),
    packageUrl: (json['packageUrl'] ?? json['downloadUrl'] ?? json['url'] ?? '')
        .toString(),
    iconUrl: (json['icon'] ?? json['iconUrl'])?.toString(),
  );
}
