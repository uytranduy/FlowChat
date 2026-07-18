enum VoiceCallStatus { idle, outgoing, incoming, connecting, active, ended }

enum CallMediaType {
  audio('audio'),
  video('video');

  const CallMediaType(this.value);

  final String value;

  bool get isVideo => this == CallMediaType.video;

  static CallMediaType fromValue(Object? value) {
    return value?.toString().trim().toLowerCase() == 'video'
        ? CallMediaType.video
        : CallMediaType.audio;
  }
}

class CallPeer {
  const CallPeer({required this.id, required this.displayName, this.avatarUrl});

  factory CallPeer.fromJson(Map<String, dynamic> json) {
    return CallPeer(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      displayName: (json['displayName'] ?? 'Người dùng FlowChat').toString(),
      avatarUrl: _nullableString(json['avatarUrl']),
    );
  }

  final String id;
  final String displayName;
  final String? avatarUrl;
}

class CallException implements Exception {
  const CallException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

String loggedOutCallMessage(String? displayName) {
  final normalizedName = displayName?.trim();
  final name = normalizedName == null || normalizedName.isEmpty
      ? 'này'
      : normalizedName;
  return 'Người dùng $name hiện đã đăng xuất khỏi tài khoản nên không thể nhận cuộc gọi.';
}

String formatCallDuration(int totalSeconds) {
  final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final seconds = safeSeconds % 60;

  if (hours > 0) {
    return '$hours giờ $minutes phút $seconds giây';
  }
  return '$minutes phút $seconds giây';
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
