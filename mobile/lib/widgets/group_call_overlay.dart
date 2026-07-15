import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
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
            child: chatOpen
                ? InCallChatPanel(
                    conversationId: call.conversationId!,
                    chatService: context.read<AppController>().chatService,
                    currentUserId:
                        context.read<AppController>().currentUser?.id ?? '',
                    isGroup: true,
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
            )
          : await widget.chatService.sendDirectMessage(
              widget.recipientId!,
              content,
              conversationId: widget.conversationId,
              filePath: file?.path,
              fileName: file?.name,
            );
      if (!mounted) return;
      composer.clear();
      pendingFile = null;
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
                  ? 'Tin nhắn được lưu vào nhóm'
                  : 'Tin nhắn được lưu vào đoạn chat',
              style: const TextStyle(color: Colors.white60),
            ),
            trailing: widget.onClose == null
                ? null
                : IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white70,
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
                      return _CallChatBubble(message: message, own: own);
                    },
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
  const _CallChatBubble({required this.message, required this.own});

  final Message message;
  final bool own;

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
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: own ? const Color(0xff7c3aed) : Colors.white12,
          borderRadius: BorderRadius.circular(15),
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
            Text(text, style: const TextStyle(color: Colors.white)),
          ],
        ),
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
