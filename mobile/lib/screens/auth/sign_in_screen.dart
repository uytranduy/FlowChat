import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_controller.dart';
import '../../widgets/auth_form_helpers.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/google_auth_button.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  static const routeName = '/signin';

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearError() {
    final controller = context.read<AppController>();
    if (controller.authError != null) controller.clearAuthError();
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (context.read<AppController>().authBusy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusManager.instance.primaryFocus?.unfocus();
    final controller = context.read<AppController>();
    controller.clearAuthError();

    var success = false;
    try {
      success = await controller.signIn(
        _usernameController.text.trim(),
        _passwordController.text,
      );
    } catch (_) {
      success = false;
    }

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      return;
    }

    _showError(
      controller.authError?.trim().isNotEmpty == true
          ? controller.authError!
          : 'Đăng nhập không thành công. Vui lòng thử lại.',
    );
  }

  Future<void> _signInWithGoogle() async {
    if (context.read<AppController>().authBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final controller = context.read<AppController>();
    final success = await controller.signInWithGoogle();
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      return;
    }
    _showError(controller.authError ?? 'Đăng nhập Google không thành công.');
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final busy = controller.authBusy;

    return AuthScaffold(
      title: 'Chào mừng quay lại',
      subtitle: 'Đăng nhập vào tài khoản FlowChat của bạn',
      footer: const AuthTermsText(),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.authError != null) ...[
                AuthErrorBanner(message: controller.authError),
                const SizedBox(height: 18),
              ],
              TextFormField(
                controller: _usernameController,
                enabled: !busy,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Tên đăng nhập',
                  hintText: 'flowchat',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) {
                  final username = value?.trim() ?? '';
                  if (username.isEmpty) return 'Vui lòng nhập tên đăng nhập';
                  if (username.length < 3) {
                    return 'Tên đăng nhập phải có ít nhất 3 ký tự';
                  }
                  return null;
                },
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                enabled: !busy,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: busy
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng nhập mật khẩu';
                  }
                  if (value.length < 6) {
                    return 'Mật khẩu phải có ít nhất 6 ký tự';
                  }
                  return null;
                },
                onChanged: (_) => _clearError(),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              FlowChatGradientButton(
                label: 'Đăng nhập',
                icon: Icons.login_rounded,
                isLoading: busy,
                onPressed: busy ? null : _submit,
              ),
              const SizedBox(height: 18),
              const GoogleAuthDivider(),
              const SizedBox(height: 18),
              GoogleAuthButton(
                label: 'Đăng nhập bằng Google',
                isLoading: busy,
                onPressed: busy ? null : _signInWithGoogle,
              ),
              const SizedBox(height: 14),
              AuthRoutePrompt(
                text: 'Chưa có tài khoản?',
                actionLabel: 'Đăng ký',
                onPressed: busy
                    ? null
                    : () {
                        controller.clearAuthError();
                        Navigator.of(context).pushReplacementNamed('/signup');
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
