import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../models/user.dart';
import '../../state/app_controller.dart';
import '../../widgets/user_avatar.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _usernameController = TextEditingController();
  final _messageController = TextEditingController();
  User? _result;
  bool _searching = false;
  bool _sending = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final username = _usernameController.text.trim();
    if (username.length < 3) {
      setState(() => _error = 'Username phải có ít nhất 3 ký tự.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searched = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await context
          .read<AppController>()
          .friendService
          .searchByUsername(username);
      if (!mounted) return;
      final me = context.read<AppController>().currentUser;
      setState(() {
        _result = result?.id == me?.id ? null : result;
        if (result?.id == me?.id) {
          _error = 'Đây là tài khoản của bạn.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendError(error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _send() async {
    final user = _result;
    if (user == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<AppController>().friendService.sendFriendRequest(
        to: user.id,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã gửi lời mời kết bạn.')));
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _friendError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm bạn mới')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Tìm chính xác bằng username',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'FlowChat sẽ không tự động gửi lời mời cho đến khi bạn xác nhận.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameController,
              autofocus: true,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                suffixIcon: IconButton(
                  tooltip: 'Tìm kiếm',
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_searched &&
                !_searching &&
                _result == null &&
                _error == null) ...[
              const SizedBox(height: 28),
              const Center(child: Text('Không tìm thấy người dùng này.')),
            ],
            if (_result case final user?) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      UserAvatar(
                        name: user.displayName,
                        avatarUrl: user.avatarUrl,
                        radius: 38,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('@${user.username}'),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _messageController,
                        maxLength: 300,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Lời giới thiệu (không bắt buộc)',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Gửi lời mời'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _friendError(Object error) {
  if (error is ApiException) return error.message;
  return 'Có lỗi kết nối. Vui lòng thử lại.';
}
