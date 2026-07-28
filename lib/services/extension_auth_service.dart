import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ExtensionAuthService {
  static const _tokenPrefix = 'hybrid_extension_oauth_token_v1_';

  final SharedPreferences _preferences;

  ExtensionAuthService(this._preferences);

  Future<String?> getToken(String extensionId) async {
    final token = _readToken(extensionId);
    if (token == null) return null;
    if (!token.isExpired) return token.accessToken;
    return token.refreshToken;
  }

  Future<OAuthToken?> getTokenDetails(String extensionId) async {
    return _readToken(extensionId);
  }

  Future<void> storeToken(String extensionId, OAuthToken token) async {
    await _preferences.setString('$_tokenPrefix${_normalizeId(extensionId)}', jsonEncode(token.toJson()));
  }

  Future<void> clearAuth(String extensionId) async {
    await _preferences.remove('$_tokenPrefix${_normalizeId(extensionId)}');
  }

  Future<bool> isAuthenticated(String extensionId) async {
    return _readToken(extensionId) != null;
  }

  Uri buildAuthorizationUri(OAuthConfig config, {required String state}) {
    return config.authorizationEndpoint.replace(
      queryParameters: <String, String>{
        ...config.authorizationEndpoint.queryParameters,
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri.toString(),
        'response_type': 'code',
        'state': state,
        if (config.scope.isNotEmpty) 'scope': config.scope.join(' '),
        ...config.extraAuthorizationParameters,
      },
    );
  }

  OAuthToken? _readToken(String extensionId) {
    final raw = _preferences.getString('$_tokenPrefix${_normalizeId(extensionId)}');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    final tokenJson = _nullableObjectMap(decoded);
    if (tokenJson == null) return null;
    return OAuthToken.fromJson(tokenJson);
  }

  static String _normalizeId(String extensionId) => extensionId.trim().toLowerCase();
}

class OAuthConfig {
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final String clientId;
  final Uri redirectUri;
  final List<String> scope;
  final Map<String, String> extraAuthorizationParameters;

  const OAuthConfig({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.clientId,
    required this.redirectUri,
    this.scope = const <String>[],
    this.extraAuthorizationParameters = const <String, String>{},
  });
}

class OAuthToken {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String tokenType;

  const OAuthToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.tokenType = 'Bearer',
  });

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 1)));
  }

  factory OAuthToken.fromJson(Map<String, dynamic> json) {
    return OAuthToken(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String?,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      tokenType: json['tokenType'] as String? ?? 'Bearer',
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    'tokenType': tokenType,
  };
}

Map<String, dynamic>? _nullableObjectMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<Object?, Object?>) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
}
