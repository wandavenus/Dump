import 'dart:convert';

class ExtensionManifest {
  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.displayName,
    required this.version,
    required this.author,
    required this.description,
    required this.types,
    required this.entrypoint,
    this.homepage,
    this.icon,
    this.permissions = const ExtensionPermissions(),
    this.settings = const [],
    this.qualityOptions = const [],
    this.minAppVersion,
    this.skipMetadataEnrichment = false,
    this.skipLyrics = false,
    this.stopProviderFallback = false,
    this.skipBuiltInFallback = false,
    this.searchBehavior,
    this.urlHandler,
    this.trackMatching,
    this.postProcessing,
    this.serviceHealth = const [],
    this.signedSession,
    this.requiredRuntimeFeatures = const [],
    this.capabilities = const {},
    this.searchUrl,
    this.downloadUrlTemplate,
  });

  final String id;
  final String name;
  final String displayName;
  final String version;
  final String author;
  final String description;
  final List<String> types;
  final String entrypoint;
  final String? homepage;
  final String? icon;
  final ExtensionPermissions permissions;
  final List<Map<String, dynamic>> settings;
  final List<Map<String, dynamic>> qualityOptions;
  final String? minAppVersion;
  final bool skipMetadataEnrichment;
  final bool skipLyrics;
  final bool stopProviderFallback;
  final bool skipBuiltInFallback;
  final Map<String, dynamic>? searchBehavior;
  final Map<String, dynamic>? urlHandler;
  final Map<String, dynamic>? trackMatching;
  final Map<String, dynamic>? postProcessing;
  final List<Map<String, dynamic>> serviceHealth;
  final Map<String, dynamic>? signedSession;
  final List<String> requiredRuntimeFeatures;
  final Map<String, dynamic> capabilities;
  final String? searchUrl;
  final String? downloadUrlTemplate;

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    final types = rawType is List
        ? rawType.map((e) => e.toString()).toList(growable: false)
        : [((rawType ?? 'metadata_provider').toString())];
    final name = (json['name'] ?? json['id'] ?? '').toString();
    return ExtensionManifest(
      id: (json['id'] ?? name).toString(),
      name: name,
      displayName: (json['displayName'] ?? json['display_name'] ?? name)
          .toString(),
      version: (json['version'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      types: types,
      entrypoint: (json['entrypoint'] ?? json['main'] ?? 'index.js').toString(),
      homepage: json['homepage']?.toString(),
      icon: json['icon']?.toString(),
      permissions: ExtensionPermissions.fromJson(
        (json['permissions'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      settings: _mapList(json['settings']),
      qualityOptions: _mapList(json['qualityOptions']),
      minAppVersion: json['minAppVersion']?.toString(),
      skipMetadataEnrichment: json['skipMetadataEnrichment'] == true,
      skipLyrics: json['skipLyrics'] == true,
      stopProviderFallback: json['stopProviderFallback'] == true,
      skipBuiltInFallback: json['skipBuiltInFallback'] == true,
      searchBehavior: (json['searchBehavior'] as Map?)?.cast<String, dynamic>(),
      urlHandler: (json['urlHandler'] as Map?)?.cast<String, dynamic>(),
      trackMatching: (json['trackMatching'] as Map?)?.cast<String, dynamic>(),
      postProcessing: (json['postProcessing'] as Map?)?.cast<String, dynamic>(),
      serviceHealth: _mapList(json['serviceHealth']),
      signedSession: (json['signedSession'] as Map?)?.cast<String, dynamic>(),
      requiredRuntimeFeatures:
          (json['requiredRuntimeFeatures'] as List? ?? const [])
              .map((e) => e.toString())
              .toList(growable: false),
      capabilities:
          (json['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {},
      searchUrl: json['searchUrl']?.toString(),
      downloadUrlTemplate: json['downloadUrlTemplate']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'version': version,
    'description': description,
    'homepage': homepage,
    'icon': icon,
    'type': types,
    'permissions': permissions.toJson(),
    'settings': settings,
    'qualityOptions': qualityOptions,
    'minAppVersion': minAppVersion,
    'skipMetadataEnrichment': skipMetadataEnrichment,
    'skipLyrics': skipLyrics,
    'stopProviderFallback': stopProviderFallback,
    'skipBuiltInFallback': skipBuiltInFallback,
    'searchBehavior': searchBehavior,
    'urlHandler': urlHandler,
    'trackMatching': trackMatching,
    'postProcessing': postProcessing,
    'serviceHealth': serviceHealth,
    'signedSession': signedSession,
    'requiredRuntimeFeatures': requiredRuntimeFeatures,
    'capabilities': capabilities,
    'entrypoint': entrypoint,
    'searchUrl': searchUrl,
    'downloadUrlTemplate': downloadUrlTemplate,
  };

  bool get hasMetadataProvider => types.contains('metadata_provider');
  bool get hasDownloadProvider => types.contains('download_provider');
  bool get hasLyricsProvider => types.contains('lyrics_provider');

  void validate() {
    if (name.trim().isEmpty) throw const FormatException('name is required');
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,127}$').hasMatch(name)) {
      throw FormatException('invalid extension name: $name');
    }
    if (version.trim().isEmpty) {
      throw const FormatException('version is required');
    }
    if (description.trim().isEmpty) {
      throw const FormatException('description is required');
    }
    if (types.isEmpty) {
      throw const FormatException('at least one type is required');
    }
    const allowed = {
      'metadata_provider',
      'download_provider',
      'lyrics_provider',
    };
    for (final type in types) {
      if (!allowed.contains(type)) {
        throw FormatException('invalid extension type: $type');
      }
    }
    if (entrypoint.trim().isEmpty ||
        entrypoint.contains('..') ||
        entrypoint.startsWith('/')) {
      throw const FormatException('invalid entrypoint');
    }
  }

  bool get isValid {
    try {
      validate();
      return true;
    } on Object {
      return false;
    }
  }

  static List<Map<String, dynamic>> _mapList(Object? value) =>
      (value as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
}

class ExtensionPermissions {
  const ExtensionPermissions({
    this.network = const [],
    this.storage = false,
    this.file = false,
    this.allowHttp = false,
  });

  final List<String> network;
  final bool storage;
  final bool file;
  final bool allowHttp;

  factory ExtensionPermissions.fromJson(Map<String, dynamic> json) =>
      ExtensionPermissions(
        network: (json['network'] as List? ?? const [])
            .map((e) => e.toString().toLowerCase())
            .toList(growable: false),
        storage: json['storage'] == true,
        file: json['file'] == true,
        allowHttp: json['allowHttp'] == true,
      );

  Map<String, dynamic> toJson() => {
    'network': network,
    'storage': storage,
    'file': file,
    if (allowHttp) 'allowHttp': true,
  };

  bool isDomainAllowed(String host) {
    final domain = host.toLowerCase().trim();
    return network.any((allowed) {
      final rule = allowed.toLowerCase().trim();
      return rule == domain ||
          (rule.startsWith('*.') && domain.endsWith(rule.substring(1)));
    });
  }
}

String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
