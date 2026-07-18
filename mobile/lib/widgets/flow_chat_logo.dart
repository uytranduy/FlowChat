import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Asset-free FlowChat brand mark, suitable for auth and app-bar surfaces.
class FlowChatLogo extends StatelessWidget {
  const FlowChatLogo({
    super.key,
    this.size = 52,
    this.showWordmark = true,
    this.wordmarkSize,
  });

  final double size;
  final bool showWordmark;
  final double? wordmarkSize;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: FlowChatColors.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: FlowChatColors.primary.withValues(alpha: 0.24),
            blurRadius: size * 0.45,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: Icon(Icons.forum_rounded, size: size * 0.55, color: Colors.white),
    );

    return Semantics(
      label: 'FlowChat',
      image: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          if (showWordmark) ...[
            SizedBox(width: size * 0.24),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: FlowChatColors.brandGradient.createShader,
              child: Text(
                'FlowChat',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontSize: wordmarkSize ?? size * 0.46,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
