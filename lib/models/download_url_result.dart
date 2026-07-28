class DownloadUrlResult {
  final Uri url;
  final Map<String, String> headers;
  final String fileExt;
  final int? contentLength;

  const DownloadUrlResult({
    required this.url,
    required this.headers,
    required this.fileExt,
    this.contentLength,
  });

  factory DownloadUrlResult.fromJson(Map<String, dynamic> json) {
    return DownloadUrlResult(
      url: Uri.parse(json['url'] as String? ?? ''),
      headers: _stringMap(json['headers']),
      fileExt: json['fileExt'] as String? ?? json['extension'] as String? ?? 'mp3',
      contentLength: (json['contentLength'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url.toString(),
        'headers': headers,
        'fileExt': fileExt,
        if (contentLength != null) 'contentLength': contentLength,
      };
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map<String, dynamic>) return const <String, String>{};
  return value.map((key, object) => MapEntry(key, object.toString()));
}
