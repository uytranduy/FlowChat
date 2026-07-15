import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/flow_chat_logo.dart';
import '../../widgets/user_avatar.dart';
import '../../models/user.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _picker = ImagePicker();
  bool _uploadingAvatar = false;

  Future<void> _pickAvatar() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null || !mounted) return;

    final imageLength = await image.length();
    if (!mounted) return;
    if (imageLength > 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ảnh đại diện phải nhỏ hơn hoặc bằng 1 MB.'),
        ),
      );
      return;
    }

    setState(() => _uploadingAvatar = true);
    final controller = context.read<AppController>();
    final success = await controller.updateAvatar(image);
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Đã cập nhật ảnh đại diện.'
              : controller.profileError ?? 'Không thể cập nhật ảnh đại diện.',
        ),
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn có thể đăng nhập lại bất cứ lúc nào.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (shouldSignOut == true && mounted) {
      await context.read<AppController>().signOut();
    }
  }

  Future<void> _editProfile(User user) async {
    final displayName = TextEditingController(text: user.displayName);
    final username = TextEditingController(text: user.username);
    final email = TextEditingController(text: user.email);
    final phone = TextEditingController(text: user.phone ?? '');
    final bio = TextEditingController(text: user.bio ?? '');
    final formKey = GlobalKey<FormState>();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chỉnh sửa thông tin'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: displayName,
                    decoration: const InputDecoration(
                      labelText: 'Tên hiển thị',
                    ),
                    validator: (value) => value?.trim().isEmpty == true
                        ? 'Không được để trống'
                        : null,
                  ),
                  TextFormField(
                    controller: username,
                    decoration: const InputDecoration(
                      labelText: 'Tên người dùng',
                    ),
                    validator: (value) => value?.trim().isEmpty == true
                        ? 'Không được để trống'
                        : null,
                  ),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) => value?.contains('@') != true
                        ? 'Email không hợp lệ'
                        : null,
                  ),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                    ),
                  ),
                  TextFormField(
                    controller: bio,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Giới thiệu'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, [
                displayName.text,
                username.text,
                email.text,
                phone.text,
                bio.text,
              ]);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    displayName.dispose();
    username.dispose();
    email.dispose();
    phone.dispose();
    bio.dispose();
    if (values == null || !mounted) return;
    final controller = context.read<AppController>();
    final success = await controller.updateProfile(
      displayName: values[0],
      username: values[1],
      email: values[2],
      phone: values[3],
      bio: values[4],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Đã cập nhật hồ sơ.'
              : controller.profileError ?? 'Không thể cập nhật hồ sơ.',
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu mới (ít nhất 8 ký tự)',
              ),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Xác nhận mật khẩu mới',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () {
              if (next.text.length < 8) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Mật khẩu mới phải có ít nhất 8 ký tự.'),
                  ),
                );
                return;
              }
              if (next.text != confirm.text) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Mật khẩu xác nhận không khớp.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, [current.text, next.text]);
            },
            child: const Text('Đổi mật khẩu'),
          ),
        ],
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (values == null || !mounted) return;
    final controller = context.read<AppController>();
    final success = await controller.changePassword(
      currentPassword: values[0],
      newPassword: values[1],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Đã đổi mật khẩu.'
              : controller.profileError ?? 'Không thể đổi mật khẩu.',
        ),
      ),
    );
  }

  Future<void> _showBlockedUsers() async {
    try {
      var users = await context
          .read<AppController>()
          .chatService
          .getBlockedUsers();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Người dùng đã chặn',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: users.isEmpty
                      ? const Center(
                          child: Text('Bạn chưa chặn người dùng nào.'),
                        )
                      : ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final blocked = users[index];
                            return ListTile(
                              leading: UserAvatar(
                                name: blocked.displayName,
                                avatarUrl: blocked.avatarUrl,
                                radius: 22,
                              ),
                              title: Text(blocked.displayName),
                              subtitle: Text('@${blocked.username}'),
                              trailing: OutlinedButton(
                                onPressed: () async {
                                  await this.context
                                      .read<AppController>()
                                      .chatService
                                      .unblockUser(blocked.id);
                                  setSheetState(
                                    () => users = users
                                        .where((user) => user.id != blocked.id)
                                        .toList(),
                                  );
                                },
                                child: const Text('Huỷ chặn'),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _updatePreference({
    bool? showOnlineStatus,
    bool? notificationsEnabled,
  }) async {
    final controller = context.read<AppController>();
    final success = await controller.updatePreferences(
      showOnlineStatus: showOnlineStatus,
      notificationsEnabled: notificationsEnabled,
    );
    if (!mounted || success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(controller.profileError ?? 'Không thể lưu cấu hình.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final user = controller.currentUser;

    return Scaffold(
      appBar: AppBar(title: const FlowChatLogo(size: 34)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: FlowChatColors.brandGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: FlowChatColors.primary.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserAvatar(
                        name: user?.displayName ?? 'FlowChat',
                        avatarUrl: user?.avatarUrl,
                        radius: 48,
                        borderColor: Colors.white,
                      ),
                      Positioned(
                        right: -6,
                        bottom: -4,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 3,
                          child: IconButton(
                            tooltip: 'Đổi ảnh đại diện',
                            onPressed: _uploadingAvatar ? null : _pickAvatar,
                            icon: _uploadingAvatar
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.photo_camera_outlined,
                                    color: FlowChatColors.primary,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    user?.displayName ?? 'Người dùng FlowChat',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user?.username ?? ''}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                  if (user?.bio?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      user!.bio!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: 'Thông tin tài khoản',
              children: [
                _InfoTile(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  value: user?.email.isNotEmpty == true
                      ? user!.email
                      : 'Chưa cập nhật',
                ),
                _InfoTile(
                  icon: Icons.phone_outlined,
                  label: 'Điện thoại',
                  value: user?.phone?.isNotEmpty == true
                      ? user!.phone!
                      : 'Chưa cập nhật',
                ),
                _InfoTile(
                  icon: Icons.notes_rounded,
                  label: 'Giới thiệu',
                  value: user?.bio?.isNotEmpty == true
                      ? user!.bio!
                      : 'Chưa có lời giới thiệu',
                  isLast: true,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: user == null ? null : () => _editProfile(user),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Chỉnh sửa hồ sơ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Cấu hình',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    controller.isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                  ),
                  title: const Text('Giao diện tối'),
                  subtitle: const Text('Được lưu riêng trên thiết bị này'),
                  value: controller.isDark,
                  onChanged: (_) => controller.toggleTheme(),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.visibility_outlined),
                  title: const Text('Hiển thị trạng thái online'),
                  subtitle: const Text(
                    'Cho phép người khác biết khi bạn trực tuyến',
                  ),
                  value: user?.showOnlineStatus ?? true,
                  onChanged: user == null
                      ? null
                      : (value) => _updatePreference(showOnlineStatus: value),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Thông báo'),
                  subtitle: const Text('Tin nhắn, cuộc gọi và lời mời kết bạn'),
                  value: user?.notificationsEnabled ?? true,
                  onChanged: user == null
                      ? null
                      : (value) =>
                            _updatePreference(notificationsEnabled: value),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('REST API'),
                  subtitle: Text(
                    AppConfig.apiBaseUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Bảo mật',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Đổi mật khẩu'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _changePassword,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.block_rounded),
                  title: const Text('Người dùng đã chặn'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showBlockedUsers,
                ),
                const Divider(height: 1),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: false,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Xoá tài khoản'),
                  subtitle: Text(
                    'Đang khóa an toàn để tránh làm mất dữ liệu trò chuyện',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: controller.authBusy ? null : _confirmSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Đăng xuất'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(value),
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}
