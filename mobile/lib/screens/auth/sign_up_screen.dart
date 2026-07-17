import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_controller.dart';
import '../../widgets/auth_form_helpers.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/google_auth_button.dart';

enum _PasswordStrength { weak, medium, strong }

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  static const routeName = '/signup';

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _specialCharacterPattern = RegExp(
    r'[!@#$%^&*(),.?":{}|<>_\-+=]',
  );

  final _formKey = GlobalKey<FormState>();
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  _PasswordStrength _passwordStrength(String password) {
    final score = <bool>[
      password.length >= 6,
      password.length >= 10,
      RegExp('[a-z]').hasMatch(password),
      RegExp('[A-Z]').hasMatch(password),
      RegExp(r'\d').hasMatch(password),
      _specialCharacterPattern.hasMatch(password),
    ].where((matched) => matched).length;
    if (score >= 5 && _specialCharacterPattern.hasMatch(password)) {
      return _PasswordStrength.strong;
    }
    if (score >= 3 &&
        password.length >= 6 &&
        _specialCharacterPattern.hasMatch(password)) {
      return _PasswordStrength.medium;
    }
    return _PasswordStrength.weak;
  }

  String _strengthLabel(_PasswordStrength strength) => switch (strength) {
    _PasswordStrength.weak => 'Yếu',
    _PasswordStrength.medium => 'Trung bình',
    _PasswordStrength.strong => 'Mạnh',
  };

  Color _strengthColor(_PasswordStrength strength) => switch (strength) {
    _PasswordStrength.weak => Colors.red,
    _PasswordStrength.medium => Colors.orange,
    _PasswordStrength.strong => Colors.green,
  };

  double _strengthValue(_PasswordStrength strength) => switch (strength) {
    _PasswordStrength.weak => 1 / 3,
    _PasswordStrength.medium => 2 / 3,
    _PasswordStrength.strong => 1,
  };

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
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
      success = await controller.signUp(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        email: _emailController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );
    } catch (_) {
      success = false;
    }

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            controller.authNotice ??
                'Đăng ký thành công! Hãy mở email và xác minh tài khoản trước khi đăng nhập.',
          ),
        ),
      );
      Navigator.of(context).pushReplacementNamed('/signin');
      return;
    }

    _showError(
      controller.authError?.trim().isNotEmpty == true
          ? controller.authError!
          : 'Đăng ký không thành công. Vui lòng thử lại.',
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
    _showError(controller.authError ?? 'Đăng ký bằng Google không thành công.');
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final busy = controller.authBusy;
    final password = _passwordController.text;
    final strength = _passwordStrength(password);

    return AuthScaffold(
      title: 'Tạo tài khoản FlowChat',
      subtitle: 'Chào mừng bạn! Hãy đăng ký để bắt đầu trò chuyện',
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
                controller: _lastNameController,
                enabled: !busy,
                autofillHints: const [AutofillHints.familyName],
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Họ',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập họ';
                  }
                  return null;
                },
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _firstNameController,
                enabled: !busy,
                autofillHints: const [AutofillHints.givenName],
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Tên',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập tên';
                  }
                  return null;
                },
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _usernameController,
                enabled: !busy,
                autofillHints: const [AutofillHints.newUsername],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Tên đăng nhập',
                  hintText: 'flowchat',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
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
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                enabled: !busy,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'ban@example.com',
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
                onChanged: (_) => _clearError(),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'FlowChat sẽ gửi liên kết xác minh tới email này. Bạn phải xác minh trước khi đăng nhập.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                enabled: !busy,
                autofillHints: const [AutofillHints.newPassword],
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
                  if (!_specialCharacterPattern.hasMatch(value)) {
                    return 'Mật khẩu phải có ký tự đặc biệt, ví dụ @ hoặc !';
                  }
                  return null;
                },
                onChanged: (_) {
                  _clearError();
                  setState(() {});
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              if (password.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Độ mạnh mật khẩu:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _strengthLabel(strength),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _strengthColor(strength),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _strengthValue(strength),
                    minHeight: 8,
                    color: _strengthColor(strength),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tối thiểu 6 ký tự và có ít nhất một ký tự đặc biệt như @ hoặc !.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FlowChatGradientButton(
                label: 'Tạo tài khoản',
                icon: Icons.person_add_alt_1_rounded,
                isLoading: busy,
                onPressed: busy ? null : _submit,
              ),
              const SizedBox(height: 18),
              const GoogleAuthDivider(),
              const SizedBox(height: 18),
              GoogleAuthButton(
                label: 'Đăng ký bằng Google',
                isLoading: busy,
                onPressed: busy ? null : _signInWithGoogle,
              ),
              const SizedBox(height: 14),
              AuthRoutePrompt(
                text: 'Đã có tài khoản?',
                actionLabel: 'Đăng nhập',
                onPressed: busy
                    ? null
                    : () {
                        controller.clearAuthError();
                        Navigator.of(context).pushReplacementNamed('/signin');
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
