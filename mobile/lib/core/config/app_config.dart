abstract final class AppConfig {
  static const String defaultApiBaseUrl = 'http://10.0.2.2:5001/api';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultApiBaseUrl,
  );

  /// OAuth 2.0 Client ID loại "Web application" dùng làm server client ID.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  static const String webRtcStunUrl = String.fromEnvironment(
    'WEBRTC_STUN_URL',
    defaultValue: 'stun:stun.l.google.com:19302',
  );

  static const String webRtcTurnUrl = String.fromEnvironment('WEBRTC_TURN_URL');

  static const String webRtcTurnUsername = String.fromEnvironment(
    'WEBRTC_TURN_USERNAME',
  );

  static const String webRtcTurnCredential = String.fromEnvironment(
    'WEBRTC_TURN_CREDENTIAL',
  );

  static String get normalizedApiBaseUrl {
    final configured = apiBaseUrl.trim();
    final value = configured.isEmpty ? defaultApiBaseUrl : configured;
    return value.endsWith('/') ? value : '$value/';
  }

  static String get socketBaseUrl {
    final uri = Uri.parse(normalizedApiBaseUrl);
    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (segments.isNotEmpty && segments.last == 'api') segments.removeLast();
    final socketPath = segments.isEmpty ? '' : '/${segments.join('/')}';
    return uri
        .replace(path: socketPath, query: null, fragment: null)
        .toString();
  }

  static List<Map<String, dynamic>> get webRtcIceServers {
    final servers = <Map<String, dynamic>>[];
    if (webRtcStunUrl.trim().isNotEmpty) {
      servers.add({'urls': webRtcStunUrl.trim()});
    }
    if (webRtcTurnUrl.trim().isNotEmpty) {
      servers.add({
        'urls': webRtcTurnUrl.trim(),
        if (webRtcTurnUsername.trim().isNotEmpty)
          'username': webRtcTurnUsername.trim(),
        if (webRtcTurnCredential.trim().isNotEmpty)
          'credential': webRtcTurnCredential.trim(),
      });
    }
    return servers;
  }
}
