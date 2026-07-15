import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Network avatar with a deterministic initials fallback and optional status.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 24,
    this.showStatus = false,
    this.isOnline = false,
    this.borderColor,
  });

  final String name;
  final String? avatarUrl;
  final double radius;
  final bool showStatus;
  final bool isOnline;
  final Color? borderColor;

  static const _fallbackColors = <Color>[
    FlowChatColors.primary,
    Color(0xFF5B67D8),
    Color(0xFFD83E8D),
    Color(0xFF168C91),
    Color(0xFFB35B18),
  ];

  String get _initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'F';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }

  Color get _fallbackColor {
    final hash = name.codeUnits.fold<int>(0, (value, unit) => value + unit);
    return _fallbackColors[hash % _fallbackColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final normalizedUrl = avatarUrl?.trim();
    final hasNetworkImage = normalizedUrl != null && normalizedUrl.isNotEmpty;
    final outline = borderColor ?? Theme.of(context).colorScheme.surface;

    final fallback = ColoredBox(
      color: _fallbackColor,
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return Semantics(
      label: 'Ảnh đại diện của $name',
      image: true,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: outline,
                ),
                child: ClipOval(
                  child: hasNetworkImage
                      ? Image.network(
                          normalizedUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback,
                          loadingBuilder: (context, child, progress) {
                            return progress == null ? child : fallback;
                          },
                        )
                      : fallback,
                ),
              ),
            ),
            if (showStatus)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: radius * 0.68,
                  height: radius * 0.68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline
                        ? FlowChatColors.online
                        : FlowChatColors.offline,
                    border: Border.all(color: outline, width: 2.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
