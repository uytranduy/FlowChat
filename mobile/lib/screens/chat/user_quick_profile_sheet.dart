import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../services/chat_service.dart';
import '../../services/friend_service.dart';
import '../../models/friend_request.dart';
import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../core/utils/presence.dart';
import '../../state/call_controller.dart';
import 'package:provider/provider.dart';
import 'chat_widgets.dart';

Future<void> showUserQuickProfileSheet(
  BuildContext context, {
  required Participant participant,
  required ChatService chatService,
  required FriendService friendService,
  required UserService userService,
  required Future<void> Function() onMessage,
  required Future<void> Function() onAudioCall,
  required Future<void> Function() onVideoCall,
  Future<void> Function()? onRelationshipChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _UserQuickProfileContent(
      participant: participant,
      chatService: chatService,
      friendService: friendService,
      userService: userService,
      onMessage: onMessage,
      onAudioCall: onAudioCall,
      onVideoCall: onVideoCall,
      onRelationshipChanged: onRelationshipChanged,
    ),
  );
}

class _UserQuickProfileContent extends StatefulWidget {
  const _UserQuickProfileContent({
    required this.participant,
    required this.chatService,
    required this.friendService,
    required this.userService,
    required this.onMessage,
    required this.onAudioCall,
    required this.onVideoCall,
    this.onRelationshipChanged,
  });

  final Participant participant;
  final ChatService chatService;
  final FriendService friendService;
  final UserService userService;
  final Future<void> Function() onMessage;
  final Future<void> Function() onAudioCall;
  final Future<void> Function() onVideoCall;
  final Future<void> Function()? onRelationshipChanged;

  @override
  State<_UserQuickProfileContent> createState() =>
      _UserQuickProfileContentState();
}

class _UserQuickProfileContentState extends State<_UserQuickProfileContent> {
  UserBlockStatus? _status;
  FriendRelationship? _relationship;
  User? _publicProfile;
  bool _loading = true;
  bool _pending = false;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _presenceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final results = await Future.wait<Object>([
        widget.chatService.getBlockStatus(widget.participant.id),
        widget.friendService.getRelationship(widget.participant.id),
        widget.userService.getPublicUser(widget.participant.id),
      ]);
      if (mounted) {
        setState(() {
          _status = results[0] as UserBlockStatus;
          _relationship = results[1] as FriendRelationship;
          _publicProfile = results[2] as User;
        });
      }
    } catch (error) {
      if (mounted) _showError(error, 'Không thể kiểm tra trạng thái chặn.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(Object error, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.toString().replaceFirst('Exception: ', '').trim().isEmpty
              ? fallback
              : error.toString().replaceFirst('Exception: ', ''),
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_pending || _status?.isBlocked == true) return;
    setState(() => _pending = true);
    Navigator.pop(context);
    await action();
  }

  Future<void> _toggleBlock() async {
    if (_pending) return;
    final unblock = _status?.isBlockedByMe == true;
    if (!unblock) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Chặn ${widget.participant.displayName}?'),
          content: const Text(
            'Hai người sẽ không thể nhắn tin hoặc gọi riêng cho tới khi bạn huỷ chặn.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Chặn'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _pending = true);
    try {
      final status = unblock
          ? await widget.chatService.unblockUser(widget.participant.id)
          : await widget.chatService.blockUser(widget.participant.id);
      if (!mounted) return;
      setState(() => _status = status);
      await widget.onRelationshipChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unblock ? 'Đã huỷ chặn người dùng.' : 'Đã chặn người dùng.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        _showError(
          error,
          unblock ? 'Không thể huỷ chặn.' : 'Không thể chặn người dùng.',
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final participant = widget.participant;
    final displayName = _publicProfile?.displayName ?? participant.displayName;
    final avatarUrl = _publicProfile?.avatarUrl ?? participant.avatarUrl;
    final username = _publicProfile?.username ?? participant.username;
    final bio = _publicProfile?.bio ?? participant.bio;
    final callController = context.watch<CallController>();
    final isOnline =
        callController.isUserOnline(participant.id) ||
        _publicProfile?.isOnline == true;
    final lastSeenAt =
        callController.recentlyOfflineAt(participant.id) ??
        _publicProfile?.lastSeenAt ??
        participant.lastSeenAt;
    final presenceVisible =
        _publicProfile?.presenceVisible ?? participant.presenceVisible;
    final disabled = _loading || _pending || _status?.isBlocked == true;
    final callDisabled = disabled || _relationship?.canCall != true;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatAvatar(label: displayName, imageUrl: avatarUrl, radius: 46),
          const SizedBox(height: 13),
          Text(
            displayName,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (username?.isNotEmpty == true)
            Text(
              '@$username',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          const SizedBox(height: 4),
          Text(
            presenceText(
              isOnline: isOnline,
              lastSeenAt: lastSeenAt,
              presenceVisible: presenceVisible,
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (bio?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(bio!, textAlign: TextAlign.center),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Người dùng chưa thêm lời giới thiệu.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 20),
          if (_status?.hasBlockedMe == true)
            const _Notice(
              text:
                  'Người này đã chặn bạn. Bạn không thể nhắn tin hoặc gọi riêng.',
            ),
          if (_status?.isBlockedByMe == true)
            const _Notice(
              text: 'Bạn đã chặn người này. Hãy huỷ chặn để tiếp tục liên hệ.',
            ),
          Row(
            children: [
              Expanded(
                child: _Action(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Nhắn riêng',
                  enabled: !disabled,
                  onTap: () => _run(widget.onMessage),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Action(
                  icon: Icons.call_outlined,
                  label: 'Gọi thoại',
                  enabled: !callDisabled,
                  onTap: () => _run(widget.onAudioCall),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Action(
                  icon: Icons.videocam_outlined,
                  label: 'Gọi video',
                  enabled: !callDisabled,
                  onTap: () => _run(widget.onVideoCall),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_loading &&
              _relationship?.isFriend == false &&
              _status?.isBlocked != true) ...[
            Text(
              'Hai người cần chấp nhận lời mời nhắn tin trước khi có thể gọi điện.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: _status?.isBlockedByMe == true
                ? OutlinedButton.icon(
                    onPressed: _pending ? null : _toggleBlock,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Huỷ chặn người dùng'),
                  )
                : FilledButton.icon(
                    onPressed: _loading || _pending ? null : _toggleBlock,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Chặn người dùng'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: enabled ? onTap : null,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
