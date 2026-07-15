import 'package:flutter/material.dart';

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final visible = message != null && message!.trim().isNotEmpty;
    final colors = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: !visible
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(message),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 20,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message!,
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Informational-only legal copy until real policy routes are available.
class AuthTermsText extends StatelessWidget {
  const AuthTermsText({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text.rich(
        TextSpan(
          style: style,
          children: const [
            TextSpan(text: 'Bằng cách tiếp tục, bạn đồng ý với '),
            TextSpan(
              text: 'Điều khoản dịch vụ',
              style: TextStyle(decoration: TextDecoration.underline),
            ),
            TextSpan(text: ' và '),
            TextSpan(
              text: 'Chính sách bảo mật',
              style: TextStyle(decoration: TextDecoration.underline),
            ),
            TextSpan(text: ' của FlowChat.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class AuthRoutePrompt extends StatelessWidget {
  const AuthRoutePrompt({
    super.key,
    required this.text,
    required this.actionLabel,
    required this.onPressed,
  });

  final String text;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text),
        TextButton(onPressed: onPressed, child: Text(actionLabel)),
      ],
    );
  }
}
