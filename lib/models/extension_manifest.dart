class ExtensionManifest {
  final String id;
  final String displayName;
  final String version;
  final String description;
  final String? author;
  final String? homepage;
  final List<String> type;
  final List<ExtensionQualityOption> qualityOptions;
  final List<ExtensionSetting> settings;
  final ExtensionPermissions permissions;
  final bool skipBuiltInFallback;

  const ExtensionManifest({
    required this.id,
    required this.displayName,
    required this.version,
    required this.description,
    this.author,
    this.homepage,
    required this.type,
    required this.qualityOptions,
    required this.settings,
    required this.permissions,
    required this.skipBuiltInFallback,
  });

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? json['id'] as String? ?? '';
    return ExtensionManifest(
      id: name,
      displayName: json['displayName'] as String? ?? name,
      version: json['version'] as String? ?? '0.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String?,
      homepage: json['homepage'] as String?,
      type: _stringList(json['type']),
      qualityOptions: _objectList(json['qualityOptions'])
          .map(ExtensionQualityOption.fromJson)
          .toList(growable: false),
      settings: _objectList(json['settings'])
          .map(ExtensionSetting.fromJson)
          .toList(growable: false),
      permissions: ExtensionPermissions.fromJson(
        _nullableObjectMap(json['permissions']) ?? const <String, dynamic>{},
      ),
      skipBuiltInFallback: json['skipBuiltInFallback'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': id,
        'displayName': displayName,
        'version': version,
        'description': description,
        if (author != null) 'author': author,
        if (homepage != null) 'homepage': homepage,
        'type': type,
        'qualityOptions': qualityOptions.map((option) => option.toJson()).toList(growable: false),
        'settings': settings.map((setting) => setting.toJson()).toList(growable: false),
        'permissions': permissions.toJson(),
        'skipBuiltInFallback': skipBuiltInFallback,
      };
}

class ExtensionQualityOption {
  final String id;
  final String label;
  final bool isDefault;

  const ExtensionQualityOption({
    required this.id,
    required this.label,
    required this.isDefault,
  });

  factory ExtensionQualityOption.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? json['value'] as String? ?? '';
    return ExtensionQualityOption(
      id: id,
      label: json['label'] as String? ?? id,
      isDefault: json['default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'default': isDefault,
      };
}

class ExtensionSetting {
  final String key;
  final String label;
  final String type;
  final Object? defaultValue;
  final bool required;

  const ExtensionSetting({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    required this.required,
  });

  factory ExtensionSetting.fromJson(Map<String, dynamic> json) {
    final key = json['key'] as String? ?? json['name'] as String? ?? '';
    return ExtensionSetting(
      key: key,
      label: json['label'] as String? ?? key,
      type: json['type'] as String? ?? 'string',
      defaultValue: json['default'],
      required: json['required'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        if (defaultValue != null) 'default': defaultValue,
        'required': required,
      };
}

class ExtensionPermissions {
  final List<String> network;

  const ExtensionPermissions({required this.network});

  factory ExtensionPermissions.fromJson(Map<String, dynamic> json) {
    return ExtensionPermissions(network: _stringList(json['network']));
  }

  Map<String, dynamic> toJson() => {'network': network};
}

List<String> _stringList(Object? value) {
  if (value is String) return [value];
  if (value is List<Object?>) return value.whereType<String>().toList(growable: false);
  return const <String>[];
}

List<Map<String, dynamic>> _objectList(Object? value) {
  if (value is! List<Object?>) return const <Map<String, dynamic>>[];
  return value.map(_nullableObjectMap).nonNulls.toList(growable: false);
}

Map<String, dynamic>? _nullableObjectMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<Object?, Object?>) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
}
