import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import 'chat_widgets.dart';
import '../../state/app_controller.dart';

Future<bool?> showConversationInfoSheet(
  BuildContext context, {
  required Conversation conversation,
  required String currentUserId,
  User? currentUser,
  Future<void> Function(Participant participant)? onParticipantTap,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ConversationInfoSheet(
      conversation: conversation,
      currentUserId: currentUserId,
      currentUser: currentUser,
      onParticipantTap: onParticipantTap,
    ),
  );
}

class _ConversationInfoSheet extends StatefulWidget {
  const _ConversationInfoSheet({
    required this.conversation,
    required this.currentUserId,
    required this.currentUser,
    required this.onParticipantTap,
  });

  final Conversation conversation;
  final String currentUserId;
  final User? currentUser;
  final Future<void> Function(Participant participant)? onParticipantTap;

  @override
  State<_ConversationInfoSheet> createState() => _ConversationInfoSheetState();
}

class _ConversationInfoSheetState extends State<_ConversationInfoSheet> {
  late Conversation conversation;
  List<User> _friends = const [];
  String? _pendingUserId;
  bool _showAddMembers = false;

  String get currentUserId => widget.currentUserId;
  User? get currentUser => widget.currentUser;
  Future<void> Function(Participant participant)? get onParticipantTap =>
      widget.onParticipantTap;

  bool get _isOwner =>
      conversation.isGroup && conversation.group?.createdById == currentUserId;
  bool get _membersCanInvite =>
      conversation.group?.allowMembersToInvite ?? true;
  bool get _membersCanRename =>
      conversation.group?.allowMembersToRename ?? true;
  bool get _isDissolved => conversation.group?.isDissolved ?? false;
  bool get _canInvite => !_isDissolved && (_isOwner || _membersCanInvite);
  bool get _canRename => !_isDissolved && (_isOwner || _membersCanRename);

  @override
  void initState() {
    super.initState();
    conversation = widget.conversation;
    if (_canInvite) _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final friends = await context
          .read<AppController>()
          .friendService
          .getFriends();
      if (mounted) setState(() => _friends = friends);
    } catch (_) {
      // The member list remains usable if loading friends fails.
    }
  }

  Future<void> _openAttachments() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _ConversationAttachmentsSheet(conversationId: conversation.id),
    );
  }

  Future<void> _addMember(User user) async {
    if (_pendingUserId != null) return;
    setState(() => _pendingUserId = user.id);
    try {
      final updated = await context
          .read<AppController>()
          .chatService
          .addGroupMember(conversation.id, user.id);
      if (!mounted) return;
      setState(() => conversation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${user.displayName} vào nhóm.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingUserId = null);
    }
  }

  Future<void> _transferOwner(Participant participant) async {
    if (_pendingUserId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chuyển quyền trưởng nhóm?'),
        content: Text(
          '${participant.displayName} sẽ trở thành trưởng nhóm mới.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Chuyển quyền'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingUserId = participant.id);
    try {
      final updated = await context
          .read<AppController>()
          .chatService
          .transferGroupOwnership(conversation.id, participant.id);
      if (!mounted) return;
      setState(() => conversation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${participant.displayName} hiện là trưởng nhóm.'),
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
    } finally {
      if (mounted) setState(() => _pendingUserId = null);
    }
  }

  Future<void> _changeInvitePermission(bool allowed) async {
    if (_pendingUserId != null) return;
    setState(() => _pendingUserId = 'settings');
    try {
      final updated = await context
          .read<AppController>()
          .chatService
          .updateGroupInvitePermission(conversation.id, allowed);
      if (!mounted) return;
      setState(() => conversation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allowed
                ? 'Mọi thành viên có thể mời thêm người.'
                : 'Chỉ trưởng nhóm có thể mời thêm người.',
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
    } finally {
      if (mounted) setState(() => _pendingUserId = null);
    }
  }

  Future<void> _changeRenamePermission(bool allowed) async {
    if (_pendingUserId != null) return;
    setState(() => _pendingUserId = 'rename-settings');
    try {
      final updated = await context
          .read<AppController>()
          .chatService
          .updateGroupRenamePermission(conversation.id, allowed);
      if (!mounted) return;
      setState(() => conversation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allowed
                ? 'Mọi thành viên có thể đổi tên nhóm.'
                : 'Chỉ trưởng nhóm có thể đổi tên nhóm.',
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
    } finally {
      if (mounted) setState(() => _pendingUserId = null);
    }
  }

  Future<void> _renameGroup() async {
    var value = conversation.group?.name.trim() ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đổi tên nhóm'),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          maxLength: 50,
          textInputAction: TextInputAction.done,
          onChanged: (nextValue) => value = nextValue,
          onFieldSubmitted: (_) {
            final normalized = value.trim();
            if (normalized.isNotEmpty) Navigator.pop(dialogContext, normalized);
          },
          decoration: const InputDecoration(hintText: 'Nhập tên nhóm mới'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final normalized = value.trim();
              if (normalized.isNotEmpty) {
                Navigator.pop(dialogContext, normalized);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name == conversation.group?.name) return;
    setState(() => _pendingUserId = 'rename');
    try {
      final updated = await context
          .read<AppController>()
          .chatService
          .renameGroup(conversation.id, name);
      if (!mounted) return;
      setState(() => conversation = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã đổi tên nhóm.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingUserId = null);
    }
  }

  Future<void> _leaveGroup() async {
    if (_pendingUserId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rời nhóm?'),
        content: Text(
          'Bạn sẽ không còn nhìn thấy ${conversation.titleFor(currentUserId)} trong danh sách chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingUserId = 'leave');
    try {
      await context.read<AppController>().chatService.leaveGroup(
        conversation.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _pendingUserId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _dissolveGroup() async {
    if (_pendingUserId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Giải tán nhóm?'),
        content: const Text(
          'Toàn bộ lịch sử tin nhắn sẽ bị xóa và không thể khôi phục. Các thành viên sẽ chỉ còn thấy thông báo nhóm đã bị giải tán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Giải tán'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingUserId = 'dissolve');
    try {
      final updated = await context
          .read<AppController>()
          .chatService
          .dissolveGroup(conversation.id);
      if (!mounted) return;
      setState(() => conversation = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nhóm đã được giải tán.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingUserId = null);
    }
  }

  Future<void> _removeDissolvedGroup() async {
    if (_pendingUserId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa nhóm?'),
        content: const Text('Nhóm sẽ biến mất khỏi danh sách chat của bạn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa nhóm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingUserId = 'remove');
    try {
      await context.read<AppController>().chatService.removeDissolvedGroup(
        conversation.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _pendingUserId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return conversation.isGroup ? _buildGroup(context) : _buildDirect(context);
  }

  Widget _buildDirect(BuildContext context) {
    final participant = conversation.otherParticipant(currentUserId);
    final title = conversation.titleFor(currentUserId);
    final username = participant?.username?.trim();
    final bio = participant?.bio?.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 28),
      child: Column(
        children: [
          ChatAvatar(
            label: title,
            imageUrl: participant?.avatarUrl,
            radius: 48,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (username != null && username.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '@$username',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _InfoCard(
            icon: Icons.person_outline_rounded,
            title: 'Thông tin người dùng',
            body: bio == null || bio.isEmpty
                ? 'Người dùng chưa thêm lời giới thiệu.'
                : bio,
          ),
          const SizedBox(height: 10),
          _AttachmentLibraryTile(onTap: _openAttachments),
          if (participant?.joinedAt case final joinedAt?) ...[
            const SizedBox(height: 10),
            _InfoCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Bắt đầu trò chuyện',
              body: DateFormat('dd/MM/yyyy').format(joinedAt.toLocal()),
            ),
          ],
          if (participant != null && onParticipantTap != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onParticipantTap!(participant);
                },
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Nhắn tin, gọi điện hoặc chặn'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroup(BuildContext context) {
    final title = conversation.titleFor(currentUserId);
    final participants = [...conversation.participants]
      ..sort((left, right) {
        if (left.id == currentUserId) return -1;
        if (right.id == currentUserId) return 1;
        return left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        );
      });
    final participantIds = participants
        .map((participant) => participant.id)
        .toSet();
    final availableFriends = _friends
        .where((friend) => !participantIds.contains(friend.id))
        .toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
            child: Column(
              children: [
                ChatAvatar(label: title, radius: 43, isGroup: true),
                const SizedBox(height: 13),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_canRename)
                  TextButton.icon(
                    onPressed: _pendingUserId == null ? _renameGroup : null,
                    icon: _pendingUserId == 'rename'
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_outlined),
                    label: const Text('Đổi tên nhóm'),
                  ),
                const SizedBox(height: 3),
                Text(
                  '${participants.length} thành viên',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_isDissolved) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Nhóm đã bị giải tán',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: _AttachmentLibraryTile(onTap: _openAttachments),
          ),
          if (_isOwner && !_isDissolved)
            Column(
              children: [
                SwitchListTile.adaptive(
                  value: _membersCanInvite,
                  onChanged: _pendingUserId == null
                      ? (value) => _changeInvitePermission(value)
                      : null,
                  title: const Text('Cho phép thành viên mời thêm người'),
                  subtitle: const Text(
                    'Khi tắt, chỉ trưởng nhóm có thể thêm thành viên.',
                  ),
                  secondary: const Icon(Icons.group_add_outlined),
                ),
                SwitchListTile.adaptive(
                  value: _membersCanRename,
                  onChanged: _pendingUserId == null
                      ? (value) => _changeRenamePermission(value)
                      : null,
                  title: const Text('Cho phép thành viên đổi tên nhóm'),
                  subtitle: const Text(
                    'Khi tắt, chỉ trưởng nhóm có thể đổi tên nhóm.',
                  ),
                  secondary: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Thành viên (${participants.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_canInvite)
                  SizedBox(
                    width: 104,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _showAddMembers = !_showAddMembers),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Thêm'),
                    ),
                  ),
              ],
            ),
          ),
          if (_canInvite && _showAddMembers)
            Container(
              constraints: const BoxConstraints(maxHeight: 190),
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: availableFriends.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(
                        child: Text('Không còn bạn bè nào có thể thêm.'),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableFriends.length,
                      itemBuilder: (context, index) {
                        final friend = availableFriends[index];
                        return ListTile(
                          leading: ChatAvatar(
                            label: friend.displayName,
                            imageUrl: friend.avatarUrl,
                            radius: 20,
                          ),
                          title: Text(friend.displayName),
                          subtitle: Text('@${friend.username}'),
                          trailing: _pendingUserId == friend.id
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  onPressed: _pendingUserId == null
                                      ? () => _addMember(friend)
                                      : null,
                                  icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                  ),
                                  tooltip: 'Thêm vào nhóm',
                                ),
                        );
                      },
                    ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
              itemCount: participants.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 66),
              itemBuilder: (context, index) {
                final participant = participants[index];
                final isMe = participant.id == currentUserId;
                final isOwner =
                    participant.id == conversation.group?.createdById;
                final username = isMe
                    ? currentUser?.username.trim()
                    : participant.username?.trim();
                final bio = isMe
                    ? currentUser?.bio?.trim()
                    : participant.bio?.trim();
                return ListTile(
                  onTap: isMe || onParticipantTap == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          onParticipantTap!(participant);
                        },
                  leading: ChatAvatar(
                    label: isMe
                        ? currentUser?.preferredName ?? participant.displayName
                        : participant.displayName,
                    imageUrl: isMe
                        ? currentUser?.avatarUrl ?? participant.avatarUrl
                        : participant.avatarUrl,
                    radius: 22,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          isMe
                              ? '${participant.displayName} (Bạn)'
                              : participant.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (isOwner) ...[
                        const SizedBox(width: 7),
                        const _OwnerBadge(),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    bio != null && bio.isNotEmpty
                        ? bio
                        : username != null && username.isNotEmpty
                        ? '@$username'
                        : 'Thành viên FlowChat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _isOwner && !_isDissolved && !isMe
                      ? _pendingUserId == participant.id
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                onPressed: _pendingUserId == null
                                    ? () => _transferOwner(participant)
                                    : null,
                                icon: const Icon(
                                  Icons.workspace_premium_outlined,
                                ),
                                tooltip: 'Chuyển quyền trưởng nhóm',
                              )
                      : null,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isDissolved)
                  FilledButton.icon(
                    onPressed: _pendingUserId == null
                        ? _removeDissolvedGroup
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    icon: _pendingUserId == 'remove'
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_outline_rounded),
                    label: const Text('Xóa nhóm'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _pendingUserId == null ? _leaveGroup : null,
                    icon: _pendingUserId == 'leave'
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: const Text('Rời nhóm'),
                  ),
                  if (_isOwner) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _pendingUserId == null ? _dissolveGroup : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      icon: _pendingUserId == 'dissolve'
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.delete_forever_outlined),
                      label: const Text('Giải tán nhóm'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentLibraryTile extends StatelessWidget {
  const _AttachmentLibraryTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.photo_library_outlined, color: colors.primary),
        title: const Text(
          'Ảnh, video và tệp đã gửi',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Xem nội dung đã chia sẻ trong cuộc trò chuyện'),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _ConversationAttachmentsSheet extends StatefulWidget {
  const _ConversationAttachmentsSheet({required this.conversationId});

  final String conversationId;

  @override
  State<_ConversationAttachmentsSheet> createState() =>
      _ConversationAttachmentsSheetState();
}

class _ConversationAttachmentsSheetState
    extends State<_ConversationAttachmentsSheet> {
  List<Message> _messages = const [];
  MessageAttachmentKind? _filter;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final messages = await context
          .read<AppController>()
          .chatService
          .getConversationAttachments(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không thể tải ảnh và tệp đã gửi.';
      });
    }
  }

  Future<void> _openImage(MessageAttachment attachment) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 4,
                  boundaryMargin: const EdgeInsets.all(80),
                  child: Center(
                    child: Image.network(
                      attachment.url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          'Không thể tải ảnh.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filled(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Đóng',
                ),
              ),
              const Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: Text(
                  'Dùng hai ngón tay để phóng to hoặc thu nhỏ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFile(MessageAttachment attachment) async {
    final uri = Uri.tryParse(attachment.url);
    if (uri == null || !uri.hasScheme) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Không thể mở tệp này.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _messages
        .where((message) {
          final attachment = message.attachment;
          return attachment != null &&
              (_filter == null || attachment.kind == _filter);
        })
        .toList(growable: false);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.photo_library_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ảnh, video và tệp đã gửi',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tất cả'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                const SizedBox(width: 7),
                ChoiceChip(
                  label: const Text('Ảnh'),
                  selected: _filter == MessageAttachmentKind.image,
                  onSelected: (_) =>
                      setState(() => _filter = MessageAttachmentKind.image),
                ),
                const SizedBox(width: 7),
                ChoiceChip(
                  label: const Text('Video'),
                  selected: _filter == MessageAttachmentKind.video,
                  onSelected: (_) =>
                      setState(() => _filter = MessageAttachmentKind.video),
                ),
                const SizedBox(width: 7),
                ChoiceChip(
                  label: const Text('Tệp'),
                  selected: _filter == MessageAttachmentKind.file,
                  onSelected: (_) =>
                      setState(() => _filter = MessageAttachmentKind.file),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : filtered.isEmpty
                ? const Center(child: Text('Chưa có nội dung phù hợp.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: .92,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final message = filtered[index];
                      final attachment = message.attachment!;
                      final isImage = attachment.isImage;
                      return Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: isImage
                              ? () => unawaited(_openImage(attachment))
                              : () => unawaited(_openFile(attachment)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: isImage
                                    ? Image.network(
                                        attachment.url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.broken_image_outlined,
                                          size: 42,
                                        ),
                                      )
                                    : Icon(
                                        attachment.isVideo
                                            ? Icons.play_circle_outline_rounded
                                            : Icons.insert_drive_file_outlined,
                                        size: 48,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(9),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      attachment.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'dd/MM/yyyy HH:mm',
                                      ).format(message.createdAt.toLocal()),
                                      maxLines: 1,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerBadge extends StatelessWidget {
  const _OwnerBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        'Trưởng nhóm',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
