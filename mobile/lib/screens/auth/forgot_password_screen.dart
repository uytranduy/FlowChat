import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/app_controller.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/gradient_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  static const routeName = '/forgot-password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool verification}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = context.read<AppController>();
    if (controller.authBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _emailController.text.trim();
    final result = verification
        ? await controller.resendVerification(email)
        : await controller.requestPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _message = result ?? controller.authError;
      _isError = result == null;
    });
  }

  Future<void> _openGoogleRecovery() async {
    await launchUrl(
      Uri.parse('https://accounts.google.com/signin/recovery'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final busy = controller.authBusy;
    final googleAccount = _message?.toLowerCase().contains('google') == true;

    return AuthScaffold(
      title: 'Quên mật khẩu',
      subtitle: 'Nhập email đăng ký để nhận liên kết đặt lại mật khẩu',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'ban@gmail.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Vui lòng nhập email';
                if (!_emailPattern.hasMatch(email)) {
                  return 'Email không hợp lệ';
                }
                return null;
              },
              onChanged: (_) {
                if (_message != null) {
                  setState(() {
                    _message = null;
                    _isError = false;
                  });
                }
              },
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isError
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_message!),
              ),
              if (googleAccount)
                TextButton(
                  onPressed: _openGoogleRecovery,
                  child: const Text('Khôi phục mật khẩu Google'),
                ),
            ],
            const SizedBox(height: 22),
            FlowChatGradientButton(
              label: 'Gửi liên kết đặt lại mật khẩu',
              icon: Icons.mark_email_read_outlined,
              isLoading: busy,
              onPressed: busy ? null : () => _submit(verification: false),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _submit(verification: true),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Gửi lại email xác minh'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Quay lại đăng nhập'),
            ),
          ],
        ),
      ),
    );
  }
}
