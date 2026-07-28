class ExtensionManifest {
  const ExtensionManifest({required this.id, required this.name, required this.version, required this.author, required this.description, required this.type, required this.entrypoint, this.searchUrl, this.downloadUrlTemplate});
  final String id, name, version, author, description, type, entrypoint;
  final String? searchUrl, downloadUrlTemplate;
  factory ExtensionManifest.fromJson(Map<String,dynamic> json) => ExtensionManifest(
    id: (json['id'] ?? '').toString(), name: (json['name'] ?? '').toString(),
    version: (json['version'] ?? '').toString(), author: (json['author'] ?? '').toString(),
    description: (json['description'] ?? '').toString(), type: (json['type'] ?? 'music').toString(),
    entrypoint: (json['entrypoint'] ?? json['main'] ?? 'index.js').toString(),
    searchUrl: json['searchUrl']?.toString(), downloadUrlTemplate: json['downloadUrlTemplate']?.toString(),
  );
  Map<String,dynamic> toJson()=> {'id':id,'name':name,'version':version,'author':author,'description':description,'type':type,'entrypoint':entrypoint,'searchUrl':searchUrl,'downloadUrlTemplate':downloadUrlTemplate};
  bool get isValid => id.isNotEmpty && name.isNotEmpty && version.isNotEmpty && entrypoint.isNotEmpty;
}
