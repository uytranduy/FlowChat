import '../core/utils/json_utils.dart';

class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    this.authProvider = 'local',
    this.avatarUrl,
    this.bio,
    this.phone,
    this.showOnlineStatus = true,
    this.notificationsEnabled = true,
    this.isOnline = false,
    this.lastSeenAt,
    this.presenceVisible = true,
    this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final id = objectId(json);
    final username = stringValue(json['username']);
    final displayName = stringValue(json['displayName'], fallback: username);
    return User(
      id: id,
      username: username,
      email: stringValue(json['email']),
      displayName: displayName,
      authProvider: stringValue(json['authProvider'], fallback: 'local'),
      avatarUrl: nullableString(json['avatarUrl']),
      bio: nullableString(json['bio']),
      phone: nullableString(json['phone']),
      showOnlineStatus: json['showOnlineStatus'] is bool
          ? json['showOnlineStatus'] as bool
          : true,
      notificationsEnabled: json['notificationsEnabled'] is bool
          ? json['notificationsEnabled'] as bool
          : true,
      isOnline: json['isOnline'] is bool ? json['isOnline'] as bool : false,
      lastSeenAt: dateTimeOrNull(json['lastSeenAt']),
      presenceVisible: json['presenceVisible'] is bool
          ? json['presenceVisible'] as bool
          : true,
      createdAt: dateTimeOrNull(json['createdAt']),
      updatedAt: dateTimeOrNull(json['updatedAt']),
    );
  }

  final String id;
  final String username;
  final String email;
  final String displayName;
  final String authProvider;
  final String? avatarUrl;
  final String? bio;
  final String? phone;
  final bool showOnlineStatus;
  final bool notificationsEnabled;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final bool presenceVisible;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get preferredName => displayName.isNotEmpty ? displayName : username;
  bool get usesGoogleAuth => authProvider == 'google';

  static User? tryParse(Object? value) {
    final map = jsonMapOrNull(value);
    if (map != null) return User.fromJson(map);

    final id = objectId(value);
    if (id.isEmpty) return null;
    return User(id: id, username: '', email: '', displayName: '');
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? displayName,
    String? authProvider,
    String? avatarUrl,
    String? bio,
    String? phone,
    bool? showOnlineStatus,
    bool? notificationsEnabled,
    bool? isOnline,
    DateTime? lastSeenAt,
    bool? presenceVisible,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      authProvider: authProvider ?? this.authProvider,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      phone: phone ?? this.phone,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      presenceVisible: presenceVisible ?? this.presenceVisible,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'username': username,
    'email': email,
    'displayName': displayName,
    'authProvider': authProvider,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    if (bio != null) 'bio': bio,
    if (phone != null) 'phone': phone,
    'showOnlineStatus': showOnlineStatus,
    'notificationsEnabled': notificationsEnabled,
    'isOnline': isOnline,
    if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
    'presenceVisible': presenceVisible,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };
}
