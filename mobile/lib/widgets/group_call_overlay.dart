import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../state/app_controller.dart';
import '../state/group_call_controller.dart';
import 'user_avatar.dart';

class GroupCallOverlay extends StatelessWidget {
  const GroupCallOverlay({super.key});
  @override
  Widget build(BuildContext context) {
    final call = context.watch<GroupCallController>();
    if (call.status == GroupCallStatus.idle) return const SizedBox.shrink();
    return Positioned.fill(
      child: Material(
        color: const Color(0xff0b1020),
        child: SafeArea(
          child: call.status == GroupCallStatus.incoming
              ? _Incoming(call: call)
              : _Room(call: call),
        ),
      ),
    );
  }
}

class _Incoming extends StatelessWidget {
  const _Incoming({required this.call});
  final GroupCallController call;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Cuộc gọi nhóm FlowChat',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Spacer(),
        UserAvatar(
          name: call.caller?.displayName ?? call.groupName,
          avatarUrl: call.caller?.avatarUrl,
          radius: 60,
        ),
        const SizedBox(height: 20),
        Text(
          call.caller?.displayName ?? 'Thành viên',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '${call.groupName} · ${call.mediaType.isVideo ? 'Gọi video' : 'Gọi thoại'}',
          style: const TextStyle(color: Colors.white70),
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FloatingActionButton(
              heroTag: 'group-reject',
              backgroundColor: Colors.red,
              onPressed: call.dismiss,
              child: const Icon(Icons.call_end, color: Colors.white),
            ),
            FloatingActionButton(
              heroTag: 'group-accept',
              backgroundColor: Colors.green,
              onPressed: () => unawaited(call.join()),
              child: Icon(
                call.mediaType.isVideo ? Icons.videocam : Icons.call,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Room extends StatefulWidget {
  const _Room({required this.call});
  final GroupCallController call;

  @override
  State<_Room> createState() => _RoomState();
}

class _RoomState extends State<_Room> {
  bool chatOpen = false;

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final members = call.participants;
    final chatConversationId = call.conversationId?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  call.groupName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${members.length} người',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: chatOpen && chatConversationId?.isNotEmpty == true
                ? InCallChatNavigator(
                    conversationId: chatConversationId!,
                    chatService: context.read<AppController>().chatService,
                    currentUserId:
                        context.read<AppController>().currentUser?.id ?? '',
                    isGroup: true,
                  )
                : chatOpen
                ? const Center(
                    child: Text(
                      'Chưa xác định được cuộc trò chuyện của cuộc gọi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: .78,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: members.length,
                    itemBuilder: (_, index) {
                      final member = members[index];
                      final isMe = member.userId == call.currentUserId;
                      final stream = isMe
                          ? call.localStream
                          : call.remoteStreams[member.userId];
                      return _Tile(member: member, stream: stream, muted: isMe);
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: call.toggleMute,
                icon: Icon(call.muted ? Icons.mic_off : Icons.mic),
              ),
              if (call.mediaType.isVideo) ...[
                const SizedBox(width: 14),
                IconButton.filledTonal(
                  onPressed: call.toggleCamera,
                  icon: Icon(
                    call.cameraEnabled ? Icons.videocam : Icons.videocam_off,
                  ),
                ),
              ],
              const SizedBox(width: 14),
              IconButton.filledTonal(
                isSelected: chatOpen,
                onPressed: () => setState(() => chatOpen = !chatOpen),
                icon: Icon(chatOpen ? Icons.close : Icons.chat_bubble_outline),
              ),
              const SizedBox(width: 14),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => unawaited(call.leave()),
                icon: const Icon(Icons.call_end, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class InCallChatNavigator extends StatelessWidget {
  const InCallChatNavigator({
    super.key,
    required this.conversationId,
    required this.chatService,
    required this.currentUserId,
    required this.isGroup,
    this.recipientId,
    this.onClose,
  });

  final String conversationId;
  final ChatService chatService;
  final String currentUserId;
  final bool isGroup;
  final String? recipientId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return HeroControllerScope.none(
      child: Navigator(
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => Material(
            color: Colors.transparent,
            child: InCallChatPanel(
              conversationId: conversationId,
              chatService: chatService,
              currentUserId: currentUserId,
              isGroup: isGroup,
              recipientId: recipientId,
              onClose: onClose,
            ),
          ),
        ),
      ),
    );
  }
}

class InCallChatPanel extends StatefulWidget {
  const InCallChatPanel({
    super.key,
    required this.conversationId,
    required this.chatService,
    required this.currentUserId,
    required this.isGroup,
    this.recipientId,
    this.onClose,
  });

  final String conversationId;
  final ChatService chatService;
  final String currentUserId;
  final bool isGroup;
  final String? recipientId;
  final VoidCallback? onClose;

  @override
  State<InCallChatPanel> createState() => _InCallChatPanelState();
}

class _InCallChatPanelState extends State<InCallChatPanel> {
  final TextEditingController composer = TextEditingController();
  final ScrollController scroll = ScrollController();
  Timer? timer;
  List<Message> messages = const [];
  bool loading = true;
  bool sending = false;
  PlatformFile? pendingFile;
  MessageAttachment? viewingImage;
  Message? replyingTo;
  String? selectedMessageId;
  final Set<String> busyMessageIds = {};
  final Map<String, GlobalKey> messageKeys = {};

  void upsert(Message message) {
    final byId = <String, Message>{for (final item in messages) item.id: item};
    byId[message.id] = message;
    final next = byId.values.toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    setState(() => messages = next);
  }

  Future<void> runMessageAction(
    Message message,
    Future<Message> Function() action,
  ) async {
    if (busyMessageIds.contains(message.id)) return;
    setState(() => busyMessageIds.add(message.id));
    try {
      final updated = await action();
      if (!mounted) return;
      upsert(updated);
      setState(() => selectedMessageId = null);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busyMessageIds.remove(message.id));
    }
  }

  Future<void> showReactions(Message message) async {
    const options = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: options
              .map(
                (item) => IconButton(
                  onPressed: () => Navigator.pop(sheetContext, item),
                  icon: Text(item, style: const TextStyle(fontSize: 25)),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    final hasSame = message.reactions.any(
      (reaction) =>
          reaction.userId == widget.currentUserId && reaction.emoji == emoji,
    );
    await runMessageAction(
      message,
      () => hasSame
          ? widget.chatService.removeReaction(message.id)
          : widget.chatService.setReaction(message.id, emoji),
    );
  }

  Future<void> togglePin(Message message) async {
    if (message.isPinned && message.pinnedBy != widget.currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ người đã ghim mới có thể bỏ ghim.')),
      );
      return;
    }
    await runMessageAction(
      message,
      () => widget.chatService.updateMessagePin(
        widget.conversationId,
        message.id,
        !message.isPinned,
      ),
    );
  }

  Future<void> recall(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thu hồi tin nhắn?'),
        content: const Text('Tin nhắn sẽ bị thu hồi với tất cả mọi người.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await runMessageAction(
        message,
        () => widget.chatService.recallMessage(message.id),
      );
    }
  }

  Future<void> jumpToMessage(String messageId) async {
    var key = messageKeys[messageId];
    if (key?.currentContext == null) {
      try {
        final around = await widget.chatService.getMessagesAround(
          widget.conversationId,
          messageId,
        );
        if (!mounted) return;
        setState(() {
          final byId = <String, Message>{
            for (final item in messages) item.id: item,
          };
          for (final item in around) {
            byId[item.id] = item;
          }
          messages = byId.values.toList()
            ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
        });
        await Future<void>.delayed(const Duration(milliseconds: 80));
        key = messageKeys[messageId];
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể tải tin nhắn gốc.')),
          );
        }
      }
    }
    if (!mounted) return;
    final targetIndex = messages.indexWhere((item) => item.id == messageId);
    if (key?.currentContext == null && targetIndex >= 0 && scroll.hasClients) {
      final fraction = messages.length <= 1
          ? 0.0
          : targetIndex / (messages.length - 1);
      await scroll.animateTo(
        scroll.position.maxScrollExtent * fraction,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      key = messageKeys[messageId];
    }
    if (!mounted) return;
    final targetContext = key?.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 350),
        alignment: .5,
      );
      if (mounted) {
        setState(() => selectedMessageId = messageId);
        Timer(const Duration(seconds: 2), () {
          if (mounted && selectedMessageId == messageId) {
            setState(() => selectedMessageId = null);
          }
        });
      }
    }
  }

  Future<void> openFinder({required bool pinned}) async {
    final selected = await showModalBottomSheet<Message>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InCallMessageFinder(
        pinned: pinned,
        load: (query) => pinned
            ? widget.chatService.getPinnedMessages(widget.conversationId)
            : widget.chatService.searchMessages(widget.conversationId, query),
      ),
    );
    if (selected != null && mounted) await jumpToMessage(selected.id);
  }

  Future<void> openAttachments() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InCallAttachmentLibrary(
        load: () => widget.chatService.getConversationAttachments(
          widget.conversationId,
        ),
        onImageTap: (attachment) {
          Navigator.pop(context);
          setState(() => viewingImage = attachment);
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(load());
    timer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(load()),
    );
  }

  Future<void> load() async {
    try {
      final page = await widget.chatService.getMessages(
        widget.conversationId,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        messages = page.messages;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final content = composer.text.trim();
    final file = pendingFile;
    if ((content.isEmpty && file == null) || sending) return;
    if (!widget.isGroup && (widget.recipientId?.isEmpty ?? true)) return;
    if (file != null && (file.path?.isEmpty ?? true)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể đọc tệp đã chọn.')),
        );
      }
      return;
    }
    setState(() => sending = true);
    try {
      final message = widget.isGroup
          ? await widget.chatService.sendGroupMessage(
              widget.conversationId,
              content,
              filePath: file?.path,
              fileName: file?.name,
              replyToMessageId: replyingTo?.id,
            )
          : await widget.chatService.sendDirectMessage(
              widget.recipientId!,
              content,
              conversationId: widget.conversationId,
              filePath: file?.path,
              fileName: file?.name,
              replyToMessageId: replyingTo?.id,
            );
      if (!mounted) return;
      composer.clear();
      pendingFile = null;
      replyingTo = null;
      setState(() {
        messages = [
          ...messages.where((item) => item.id != message.id),
          message,
        ];
      });
      await load();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể gửi tin nhắn hoặc tệp. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> pickAttachment() async {
    if (sending) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      setState(() => pendingFile = result.files.single);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở trình chọn tệp.')),
        );
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = viewingImage;
    if (image != null) {
      return _InCallImageViewer(
        attachment: image,
        onClose: () => setState(() => viewingImage = null),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            title: const Text(
              'Chat trong cuộc gọi',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              widget.isGroup
                  ? 'Tin nhắn và tệp được lưu vào nhóm'
                  : 'Tin nhắn và tệp được lưu vào đoạn chat',
              style: const TextStyle(color: Colors.white60),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  color: const Color(0xff1e293b),
                  iconColor: Colors.white70,
                  tooltip: 'Công cụ trò chuyện',
                  onSelected: (value) {
                    if (value == 'search') unawaited(openFinder(pinned: false));
                    if (value == 'pinned') unawaited(openFinder(pinned: true));
                    if (value == 'media') unawaited(openAttachments());
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'search',
                      child: ListTile(
                        leading: Icon(Icons.search, color: Colors.white70),
                        title: Text(
                          'Tìm kiếm tin nhắn',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'pinned',
                      child: ListTile(
                        leading: Icon(
                          Icons.push_pin_outlined,
                          color: Colors.white70,
                        ),
                        title: Text(
                          'Tin nhắn đã ghim',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'media',
                      child: ListTile(
                        leading: Icon(
                          Icons.perm_media_outlined,
                          color: Colors.white70,
                        ),
                        title: Text(
                          'Ảnh, video và tệp',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.onClose != null)
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white70,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa có tin nhắn',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: messages.length,
                    itemBuilder: (_, index) {
                      final message = messages[index];
                      final own = message.isOwn(widget.currentUserId);
                      return _CallChatBubble(
                        key: messageKeys.putIfAbsent(message.id, GlobalKey.new),
                        message: message,
                        own: own,
                        currentUserId: widget.currentUserId,
                        selected: selectedMessageId == message.id,
                        busy: busyMessageIds.contains(message.id),
                        onSelect: () => setState(
                          () => selectedMessageId =
                              selectedMessageId == message.id
                              ? null
                              : message.id,
                        ),
                        onReply: () => setState(() {
                          replyingTo = message;
                          selectedMessageId = null;
                        }),
                        onRecall: () => unawaited(recall(message)),
                        onPin: () => unawaited(togglePin(message)),
                        onReact: () => unawaited(showReactions(message)),
                        onReactionTap: (emoji) =>
                            unawaited(showReactions(message)),
                        onReplyTap: message.replyTo == null
                            ? null
                            : () => unawaited(
                                jumpToMessage(message.replyTo!.messageId),
                              ),
                        onImageTap: (attachment) =>
                            setState(() => viewingImage = attachment),
                      );
                    },
                  ),
          ),
          if (replyingTo case final reply?)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
                border: const Border(
                  left: BorderSide(color: Color(0xffc084fc), width: 3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.reply_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      reply.content.isEmpty ? 'Tin nhắn' : reply.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => replyingTo = null),
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          if (pendingFile case final file?)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.attach_file_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: sending
                          ? null
                          : () => setState(() => pendingFile = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: sending ? null : () => unawaited(pickAttachment()),
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: composer,
                    enabled: !sending,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => unawaited(send()),
                    decoration: InputDecoration(
                      hintText: 'Nhắn tin...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black26,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed:
                      sending ||
                          (composer.text.trim().isEmpty && pendingFile == null)
                      ? null
                      : () => unawaited(send()),
                  icon: sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallChatBubble extends StatelessWidget {
  const _CallChatBubble({
    super.key,
    required this.message,
    required this.own,
    required this.currentUserId,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onReply,
    required this.onRecall,
    required this.onPin,
    required this.onReact,
    required this.onReactionTap,
    required this.onReplyTap,
    required this.onImageTap,
  });

  final Message message;
  final bool own;
  final String currentUserId;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onReply;
  final VoidCallback onRecall;
  final VoidCallback onPin;
  final VoidCallback onReact;
  final ValueChanged<String> onReactionTap;
  final VoidCallback? onReplyTap;
  final ValueChanged<MessageAttachment> onImageTap;

  @override
  Widget build(BuildContext context) {
    final text = message.isRecalled
        ? 'Tin nhắn đã thu hồi'
        : message.attachment != null
        ? '${message.attachment!.isImage
              ? '📷'
              : message.attachment!.isVideo
              ? '🎬'
              : '📎'} ${message.content.trim().isEmpty ? message.attachment!.fileName : message.content}'
        : message.isCall
        ? '📞 Lịch sử cuộc gọi'
        : message.content;
    final reactions = <String, int>{};
    for (final reaction in message.reactions) {
      reactions[reaction.emoji] = (reactions[reaction.emoji] ?? 0) + 1;
    }
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: own
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (selected && !message.isRecalled)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 4,
                children: [
                  IconButton.filledTonal(
                    onPressed: busy ? null : onReply,
                    icon: const Icon(Icons.reply_rounded),
                    tooltip: 'Trả lời',
                  ),
                  IconButton.filledTonal(
                    onPressed: busy ? null : onReact,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    tooltip: 'Thả cảm xúc',
                  ),
                  IconButton.filledTonal(
                    onPressed: busy ? null : onPin,
                    icon: Icon(
                      message.isPinned
                          ? Icons.push_pin_outlined
                          : Icons.push_pin_rounded,
                    ),
                    tooltip: message.isPinned ? 'Bỏ ghim' : 'Ghim',
                  ),
                  if (own && !message.isCall)
                    IconButton.filledTonal(
                      onPressed: busy ? null : onRecall,
                      icon: const Icon(Icons.undo_rounded),
                      tooltip: 'Thu hồi',
                    ),
                ],
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: message.isRecalled ? null : onSelect,
            onLongPress: message.isRecalled ? null : onSelect,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: own ? const Color(0xff7c3aed) : Colors.white12,
                borderRadius: BorderRadius.circular(15),
                border: selected
                    ? Border.all(color: const Color(0xffffc107), width: 2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!own)
                    Text(
                      message.sender?.preferredName ?? 'Thành viên',
                      style: const TextStyle(
                        color: Color(0xffd8b4fe),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (message.isPinned)
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.push_pin_rounded,
                            color: Colors.white70,
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Đã ghim',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.replyTo case final reply?)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onReplyTap,
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 5, bottom: 4),
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          border: Border(
                            left: BorderSide(
                              color: Color(0xffd8b4fe),
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          reply.content.isEmpty
                              ? 'Tin nhắn gốc'
                              : reply.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  if (message.attachment case final attachment?)
                    if (attachment.isImage) ...[
                      const SizedBox(height: 4),
                      Semantics(
                        button: true,
                        label: 'Phóng to ảnh ${attachment.fileName}',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onImageTap(attachment),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 120,
                                maxWidth: 250,
                                maxHeight: 180,
                              ),
                              child: Image.network(
                                attachment.url,
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null
                                    ? child
                                    : const SizedBox(
                                        width: 120,
                                        height: 120,
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                errorBuilder: (_, _, _) => const SizedBox(
                                  width: 120,
                                  height: 80,
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  if (message.attachment?.isImage != true ||
                      message.content.trim().isNotEmpty)
                    Text(text, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
          if (reactions.isNotEmpty)
            Wrap(
              spacing: 4,
              children: reactions.entries
                  .map((entry) {
                    final mine = message.reactions.any(
                      (reaction) =>
                          reaction.userId == currentUserId &&
                          reaction.emoji == entry.key,
                    );
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: mine
                          ? const Color(0xff6d28d9)
                          : Colors.white12,
                      label: Text(
                        '${entry.key} ${entry.value}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                      onPressed: busy ? null : () => onReactionTap(entry.key),
                    );
                  })
                  .toList(growable: false),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _InCallMessageFinder extends StatefulWidget {
  const _InCallMessageFinder({required this.pinned, required this.load});

  final bool pinned;
  final Future<List<Message>> Function(String query) load;

  @override
  State<_InCallMessageFinder> createState() => _InCallMessageFinderState();
}

class _InCallMessageFinderState extends State<_InCallMessageFinder> {
  final controller = TextEditingController();
  List<Message> results = const [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.pinned) unawaited(search());
  }

  Future<void> search() async {
    if (!widget.pinned && controller.text.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      final next = await widget.load(controller.text.trim());
      if (mounted) setState(() => results = next);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .72,
    child: Column(
      children: [
        ListTile(
          leading: Icon(
            widget.pinned ? Icons.push_pin_rounded : Icons.search_rounded,
          ),
          title: Text(
            widget.pinned ? 'Tin nhắn đã ghim' : 'Tìm kiếm tin nhắn',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (!widget.pinned)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (_) => unawaited(search()),
              decoration: InputDecoration(
                hintText: 'Nhập nội dung hoặc tên tệp...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () => unawaited(search()),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : results.isEmpty
              ? Center(
                  child: Text(
                    widget.pinned
                        ? 'Chưa có tin nhắn đã ghim.'
                        : 'Không tìm thấy tin nhắn.',
                  ),
                )
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (_, index) {
                    final message = results[index];
                    final preview = message.isCall
                        ? '📞 Lịch sử cuộc gọi'
                        : message.attachment != null
                        ? '📎 ${message.attachment!.fileName}'
                        : message.content;
                    return ListTile(
                      leading: message.isPinned
                          ? const Icon(Icons.push_pin, color: Colors.deepPurple)
                          : const Icon(Icons.chat_bubble_outline),
                      title: Text(
                        preview.isEmpty ? 'Tin nhắn' : preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, message),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _InCallAttachmentLibrary extends StatefulWidget {
  const _InCallAttachmentLibrary({
    required this.load,
    required this.onImageTap,
  });

  final Future<List<Message>> Function() load;
  final ValueChanged<MessageAttachment> onImageTap;

  @override
  State<_InCallAttachmentLibrary> createState() =>
      _InCallAttachmentLibraryState();
}

class _InCallAttachmentLibraryState extends State<_InCallAttachmentLibrary> {
  List<Message> messages = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget
          .load()
          .then((value) {
            if (mounted) {
              setState(() {
                messages = value;
                loading = false;
              });
            }
          })
          .catchError((_) {
            if (mounted) setState(() => loading = false);
          }),
    );
  }

  Future<void> openExternal(MessageAttachment attachment) async {
    final uri = Uri.tryParse(attachment.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .82,
    child: Column(
      children: [
        const ListTile(
          leading: Icon(Icons.perm_media_outlined),
          title: Text(
            'Ảnh, video và tệp đã gửi',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
              ? const Center(child: Text('Chưa có ảnh, video hoặc tệp.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 9,
                    mainAxisSpacing: 9,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (_, index) {
                    final attachment = messages[index].attachment!;
                    return Material(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(13),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: attachment.isImage
                            ? () => widget.onImageTap(attachment)
                            : () => unawaited(openExternal(attachment)),
                        child: Column(
                          children: [
                            Expanded(
                              child: attachment.isImage
                                  ? Image.network(
                                      attachment.url,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.broken_image),
                                    )
                                  : Icon(
                                      attachment.isVideo
                                          ? Icons.play_circle_outline
                                          : Icons.insert_drive_file_outlined,
                                      size: 48,
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                attachment.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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

class _InCallImageViewer extends StatelessWidget {
  const _InCallImageViewer({required this.attachment, required this.onClose});

  final MessageAttachment attachment;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
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
                  loadingBuilder: (context, child, progress) => progress == null
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
            child: Semantics(
              button: true,
              label: 'Đóng trình xem ảnh',
              child: IconButton.filled(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
          const Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Dùng hai ngón tay để phóng to hoặc thu nhỏ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    required this.member,
    required this.stream,
    required this.muted,
  });
  final GroupCallMember member;
  final MediaStream? stream;
  final bool muted;
  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool ready = false;
  @override
  void initState() {
    super.initState();
    unawaited(
      renderer.initialize().then((_) {
        if (mounted) {
          setState(() {
            ready = true;
            renderer.srcObject = widget.stream;
          });
        }
      }),
    );
  }

  @override
  void didUpdateWidget(covariant _Tile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (ready && oldWidget.stream != widget.stream) {
      renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    renderer.srcObject = null;
    unawaited(renderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo =
        widget.stream?.getVideoTracks().any((track) => track.enabled) == true;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: Colors.black38,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready && hasVideo)
              RTCVideoView(
                renderer,
                mirror: widget.muted,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(
                child: UserAvatar(
                  name: widget.member.displayName,
                  avatarUrl: widget.member.avatarUrl,
                  radius: 38,
                ),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.member.displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
