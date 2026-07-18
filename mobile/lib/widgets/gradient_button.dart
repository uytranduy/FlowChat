import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Primary FlowChat call-to-action with the brand gradient and loading state.
class FlowChatGradientButton extends StatelessWidget {
  const FlowChatGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final borderRadius = BorderRadius.circular(16);
    final foreground = Colors.white.withValues(alpha: enabled ? 1 : 0.78);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: enabled ? FlowChatColors.brandGradient : null,
          color: enabled
              ? null
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.18),
          borderRadius: borderRadius,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: FlowChatColors.primary.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: borderRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: isLoading
                      ? SizedBox(
                          key: const ValueKey('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: foreground,
                          ),
                        )
                      : Row(
                          key: const ValueKey('label'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, size: 19, color: foreground),
                              const SizedBox(width: 9),
                            ],
                            Text(
                              label,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
