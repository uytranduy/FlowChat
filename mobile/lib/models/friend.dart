import '../core/utils/json_utils.dart';
import 'user.dart';

class Friend {
  const Friend({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: objectId(json),
      username: stringValue(json['username']),
      displayName: stringValue(json['displayName']),
      avatarUrl: nullableString(json['avatarUrl']),
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  static Friend? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map == null) return null;
    return Friend.fromJson(map);
  }

  User toUser() => User(
    id: id,
    username: username,
    email: '',
    displayName: displayName,
    avatarUrl: avatarUrl,
  );
}
