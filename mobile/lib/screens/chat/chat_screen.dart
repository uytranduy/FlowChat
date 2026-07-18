import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/friend_request.dart';
import '../../models/voice_call.dart';
import '../../state/app_controller.dart';
import '../../state/call_controller.dart';
import '../../state/group_call_controller.dart';
import 'chat_widgets.dart';
import 'conversation_info_sheet.dart';
import 'user_quick_profile_sheet.dart';
import '../../core/utils/presence.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversation,
    this.onConversationChanged,
  });

  final Conversation conversation;
  final VoidCallback? onConversationChanged;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const _pageSize = 50;
  static const _pollInterval = Duration(seconds: 4);
  static const _reactionOptions = ['👍', '❤️', '😂', '😮', '😢', '😡'];
  static const _maxImageBytes = 10 * 1024 * 1024;
  static const _maxVideoBytes = 50 * 1024 * 1024;
  static const _maxFileBytes = 20 * 1024 * 1024;

  final _composerController = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  List<Message> _messages = const [];
  List<Message> _pinnedMessages = const [];
  Timer? _pollTimer;
  Timer? _presenceTimer;
  Timer? _messageHighlightTimer;
  final List<Timer> _callHistoryRefreshTimers = [];
  CallController? _callController;
  int _handledCallHistoryRevision = 0;
  int _handledRelationshipRevision = 0;
  int _handledConversationRevision = 0;
  int _handledMessagePinRevision = 0;
  Conversation? _latestConversation;
  String? _nextCursor;
  String? _initialError;
  bool _initialized = false;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _polling = false;
  bool _loadingPinned = false;
  bool _sending = false;
  bool _markingSeen = false;
  bool _syncFailed = false;
  _PendingAttachment? _pendingAttachment;
  double? _uploadProgress;
  String? _selectedMessageId;
  String? _highlightedMessageId;
  FriendRelationship? _relationship;
  bool _relationshipPending = false;
  Message? _replyingTo;
  final Set<String> _messageActionBusy = {};

  AppController get _app => context.read<AppController>();
  String get _currentUserId => _app.currentUser?.id ?? '';
  Conversation get _conversation => _latestConversation ?? widget.conversation;
  bool get _isGroupDissolved =>
      _conversation.isGroup && (_conversation.group?.isDissolved ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
    _composerController.addListener(_handleComposerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final callController = context.read<CallController>();
    if (!identical(_callController, callController)) {
      _callController?.removeListener(_handleCallHistorySignal);
      _callController = callController;
      _handledCallHistoryRevision = callController.callHistoryRevision;
      _handledRelationshipRevision = callController.relationshipRevision;
      _handledConversationRevision = callController.conversationRevision;
      _handledMessagePinRevision = callController.messagePinRevision;
      callController.addListener(_handleCallHistorySignal);
    }
    if (_initialized) return;
    _initialized = true;
    unawaited(_loadInitial());
    unawaited(_loadPinnedMessages());
    unawaited(_loadRelationship());
    unawaited(_refreshActiveGroupCall());
    _startPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startPolling();
        unawaited(_pollMessages());
        unawaited(_markAsSeen());
        unawaited(_refreshActiveGroupCall());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _pollTimer?.cancel();
        _pollTimer = null;
        _presenceTimer?.cancel();
        _presenceTimer = null;
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callController?.removeListener(_handleCallHistorySignal);
    for (final timer in _callHistoryRefreshTimers) {
      timer.cancel();
    }
    _callHistoryRefreshTimers.clear();
    _pollTimer?.cancel();
    _presenceTimer?.cancel();
    _messageHighlightTimer?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _composerController
      ..removeListener(_handleComposerChanged)
      ..dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) setState(() {});
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.pixels > 120) {
      return;
    }
    unawaited(_loadOlder());
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _presenceTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollMessages());
      unawaited(_refreshActiveGroupCall());
    });
    _presenceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshActiveGroupCall() async {
    if (!widget.conversation.isGroup) return;
    await context.read<GroupCallController>().checkActive(
      widget.conversation.id,
    );
  }

  void _handleCallHistorySignal() {
    final callController = _callController;
    if (!mounted || callController == null) return;

    final relationshipRevision = callController.relationshipRevision;
    if (relationshipRevision > _handledRelationshipRevision) {
      _handledRelationshipRevision = relationshipRevision;
      if (widget.conversation.isDirect) unawaited(_loadRelationship());
    }

    final conversationRevision = callController.conversationRevision;
    if (conversationRevision > _handledConversationRevision) {
      _handledConversationRevision = conversationRevision;
      unawaited(_refreshConversationState());
    }

    final pinRevision = callController.messagePinRevision;
    if (pinRevision > _handledMessagePinRevision) {
      _handledMessagePinRevision = pinRevision;
      if (callController.messagePinConversationId == widget.conversation.id) {
        unawaited(_loadPinnedMessages());
        unawaited(_pollMessages());
      }
    }

    final revision = callController.callHistoryRevision;
    if (revision <= _handledCallHistoryRevision) return;
    _handledCallHistoryRevision = revision;
    if (callController.callHistoryConversationId != widget.conversation.id) {
      return;
    }

    for (final timer in _callHistoryRefreshTimers) {
      timer.cancel();
    }
    _callHistoryRefreshTimers.clear();

    // The server closes the call UI before the call-history message finishes
    // persisting. Refresh now for the normal socket path and retry briefly for
    // that small race; the regular four-second polling remains the fallback.
    unawaited(_pollMessages());
    for (final delay in const [
      Duration(milliseconds: 350),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2200),
    ]) {
      late final Timer timer;
      timer = Timer(delay, () {
        _callHistoryRefreshTimers.remove(timer);
        if (mounted) unawaited(_pollMessages());
      });
      _callHistoryRefreshTimers.add(timer);
    }
  }

  Future<void> _refreshConversationState() async {
    try {
      final conversations = await _app.chatService.getConversations();
      final latest = conversations
          .where((item) => item.id == widget.conversation.id)
          .firstOrNull;
      if (latest == null || !mounted) return;
      final becameDissolved =
          latest.group?.isDissolved == true && !_isGroupDissolved;
      MessagePage? page;
      if (becameDissolved) {
        page = await _app.chatService.getMessages(latest.id, limit: _pageSize);
      }
      if (!mounted) return;
      setState(() {
        _latestConversation = latest;
        if (page != null) {
          _messages = page.messages;
          _nextCursor = page.nextCursor;
          _replyingTo = null;
          _selectedMessageId = null;
          _pendingAttachment = null;
        }
      });
      widget.onConversationChanged?.call();
    } catch (_) {
      // Regular polling remains the fallback when a realtime refresh fails.
    }
  }

  Future<void> _loadInitial() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _initialError = null;
      });
    }

    try {
      final page = await _app.chatService.getMessages(
        widget.conversation.id,
        limit: _pageSize,
      );
      if (!mounted) return;

      setState(() {
        _messages = _deduplicateAndSort(page.messages);
        _nextCursor = page.nextCursor;
        _loading = false;
        _initialError = null;
        _syncFailed = false;
      });
      _scrollToBottom(afterLayout: true);
      unawaited(_markAsSeen());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialError = friendlyError(
          error,
          fallback: 'Không thể tải tin nhắn.',
        );
      });
    }
  }

  Future<void> _loadOlder() async {
    final cursor = _nextCursor;
    if (_loading || _loadingOlder || cursor == null) return;

    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldOffset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;

    setState(() => _loadingOlder = true);
    try {
      final page = await _app.chatService.getMessages(
        widget.conversation.id,
        limit: _pageSize,
        cursor: cursor,
      );
      if (!mounted) return;

      setState(() {
        _messages = _deduplicateAndSort([...page.messages, ..._messages]);
        _nextCursor = page.nextCursor;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final addedExtent =
            _scrollController.position.maxScrollExtent - oldExtent;
        final target = (oldOffset + addedExtent)
            .clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            )
            .toDouble();
        _scrollController.jumpTo(target);
      });
    } catch (error) {
      if (mounted) {
        _showError(error, fallback: 'Không thể tải tin nhắn cũ hơn.');
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _loadPinnedMessages() async {
    if (_loadingPinned) return;
    _loadingPinned = true;
    try {
      final messages = await _app.chatService.getPinnedMessages(
        widget.conversation.id,
      );
      if (!mounted) return;
      final previousIds = _pinnedMessages.map((item) => item.id).join(',');
      final nextIds = messages.map((item) => item.id).join(',');
      if (previousIds != nextIds ||
          messages.any((message) {
            final previous = _pinnedMessages
                .where((item) => item.id == message.id)
                .firstOrNull;
            return previous == null ||
                hasMessagePresentationChanged(previous, message);
          })) {
        setState(() => _pinnedMessages = messages);
      }
    } catch (_) {
      // Đồng bộ định kỳ sẽ tự thử lại khi kết nối ổn định.
    } finally {
      _loadingPinned = false;
    }
  }

  Future<void> _pollMessages() async {
    if (_loading || _polling || _sending) return;
    _polling = true;
    unawaited(_loadPinnedMessages());

    try {
      final page = await _app.chatService.getMessages(
        widget.conversation.id,
        limit: _pageSize,
      );
      if (!mounted) return;

      final previousById = <String, Message>{
        for (final message in _messages) message.id: message,
      };
      final hasNewMessage = page.messages.any(
        (message) => !previousById.containsKey(message.id),
      );
      final hasUpdatedMessage = page.messages.any((message) {
        final previous = previousById[message.id];
        return previous != null &&
            hasMessagePresentationChanged(previous, message);
      });
      final wasNearBottom = _isNearBottom;

      if (hasNewMessage || hasUpdatedMessage) {
        setState(() {
          _messages = _deduplicateAndSort([..._messages, ...page.messages]);
          final reply = _replyingTo;
          if (reply != null) {
            for (final message in page.messages) {
              if (message.id == reply.id) {
                _replyingTo = message.isRecalled ? null : message;
                break;
              }
            }
          }
        });
        widget.onConversationChanged?.call();
        if (hasNewMessage && widget.conversation.isDirect) {
          unawaited(_loadRelationship());
        }
        if (hasNewMessage && wasNearBottom) {
          _scrollToBottom(afterLayout: true);
        }
        if (page.messages.any(
          (message) => message.senderId != _currentUserId,
        )) {
          unawaited(_markAsSeen());
        }
      }

      if (_syncFailed) setState(() => _syncFailed = false);
    } catch (_) {
      if (mounted && !_syncFailed) setState(() => _syncFailed = true);
    } finally {
      _polling = false;
    }
  }

  Future<void> _markAsSeen() async {
    if (_markingSeen || _currentUserId.isEmpty) return;
    _markingSeen = true;
    try {
      await _app.chatService.markAsSeen(widget.conversation.id);
      widget.onConversationChanged?.call();
    } catch (_) {
      // Polling will retry after the next successful refresh.
    } finally {
      _markingSeen = false;
    }
  }

  Future<void> _loadRelationship() async {
    if (!widget.conversation.isDirect) {
      if (mounted) setState(() => _relationship = null);
      return;
    }
    final other = widget.conversation.otherParticipant(_currentUserId);
    if (other == null) return;
    try {
      final relationship = await _app.friendService.getRelationship(other.id);
      if (mounted) setState(() => _relationship = relationship);
    } catch (_) {
      // Sending/calling remains protected by the backend if status refresh fails.
    }
  }

  Future<void> _acceptMessageRequest() async {
    final requestId = _relationship?.requestId;
    if (requestId == null || _relationshipPending) return;
    setState(() => _relationshipPending = true);
    try {
      await _app.friendService.acceptFriendRequest(requestId);
      await _loadRelationship();
      widget.onConversationChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã chấp nhận. Hai bạn hiện đã là bạn bè.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(error, fallback: 'Không thể chấp nhận lời mời.');
    } finally {
      if (mounted) setState(() => _relationshipPending = false);
    }
  }

  Future<void> _blockMessageRequester() async {
    final other = widget.conversation.otherParticipant(_currentUserId);
    if (other == null || _relationshipPending) return;
    setState(() => _relationshipPending = true);
    try {
      await _app.chatService.blockUser(other.id);
      await _loadRelationship();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã chặn người dùng.')));
      }
    } catch (error) {
      if (mounted) _showError(error, fallback: 'Không thể chặn người dùng.');
    } finally {
      if (mounted) setState(() => _relationshipPending = false);
    }
  }

  List<Message> _deduplicateAndSort(Iterable<Message> incoming) {
    final byId = <String, Message>{};
    for (final message in incoming) {
      byId[message.id] = message;
    }
    final result = byId.values.toList()
      ..sort((a, b) {
        final byDate = _messageDate(a).compareTo(_messageDate(b));
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    return result;
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
        180;
  }

  void _scrollToBottom({bool afterLayout = false}) {
    void scroll() {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }

    if (afterLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) => scroll());
    } else {
      scroll();
    }
  }

  Future<void> _sendMessage() async {
    final content = _composerController.text.trim();
    final pendingAttachment = _pendingAttachment;
    if ((content.isEmpty && pendingAttachment == null) || _sending) return;
    final replyTo = _replyingTo;

    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _uploadProgress = pendingAttachment == null ? null : 0;
    });

    void onSendProgress(int sent, int total) {
      if (!mounted || total <= 0) return;
      setState(() => _uploadProgress = (sent / total).clamp(0, 1).toDouble());
    }

    try {
      late final Message sent;
      if (widget.conversation.isGroup) {
        sent = await _app.chatService.sendGroupMessage(
          widget.conversation.id,
          content,
          replyToMessageId: replyTo?.id,
          filePath: pendingAttachment?.file.path,
          fileName: pendingAttachment?.file.name,
          onSendProgress: pendingAttachment == null ? null : onSendProgress,
        );
      } else {
        final recipient = widget.conversation.otherParticipant(_currentUserId);
        if (recipient == null || recipient.id.isEmpty) {
          throw StateError('Không tìm thấy người nhận của cuộc trò chuyện.');
        }
        sent = await _app.chatService.sendDirectMessage(
          recipient.id,
          content,
          conversationId: widget.conversation.id,
          replyToMessageId: replyTo?.id,
          filePath: pendingAttachment?.file.path,
          fileName: pendingAttachment?.file.name,
          onSendProgress: pendingAttachment == null ? null : onSendProgress,
        );
      }

      if (!mounted) return;
      _composerController.clear();
      setState(() {
        _messages = _deduplicateAndSort([..._messages, sent]);
        if (_replyingTo?.id == replyTo?.id) _replyingTo = null;
        if (_pendingAttachment == pendingAttachment) _pendingAttachment = null;
        _uploadProgress = null;
        _selectedMessageId = null;
        _syncFailed = false;
      });
      widget.onConversationChanged?.call();
      if (widget.conversation.isDirect) unawaited(_loadRelationship());
      _scrollToBottom(afterLayout: true);
    } catch (error) {
      if (mounted) _showError(error, fallback: 'Không thể gửi tin nhắn.');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _pickAttachment() async {
    if (_sending) return;
    final kind = await showModalBottomSheet<_AttachmentPickKind>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Gửi ảnh'),
                subtitle: const Text('Tối đa 10 MB'),
                onTap: () =>
                    Navigator.pop(sheetContext, _AttachmentPickKind.image),
              ),
              ListTile(
                leading: const Icon(Icons.video_file_outlined),
                title: const Text('Gửi video'),
                subtitle: const Text('Tối đa 50 MB'),
                onTap: () =>
                    Navigator.pop(sheetContext, _AttachmentPickKind.video),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_rounded),
                title: const Text('Gửi tệp'),
                subtitle: const Text('PDF, Word, ZIP… tối đa 20 MB'),
                onTap: () =>
                    Navigator.pop(sheetContext, _AttachmentPickKind.file),
              ),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: switch (kind) {
          _AttachmentPickKind.image => FileType.image,
          _AttachmentPickKind.video => FileType.video,
          _AttachmentPickKind.file => FileType.any,
        },
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      if (file.path == null || file.path!.trim().isEmpty) {
        throw StateError('Không thể đọc đường dẫn của tệp đã chọn.');
      }

      final extension = (file.extension ?? _extensionOf(file.name))
          .toLowerCase();
      final actualKind = _attachmentKindFor(file, fallback: kind);
      final supported = switch (actualKind) {
        _AttachmentPickKind.image => _imageExtensions.contains(extension),
        _AttachmentPickKind.video => _videoExtensions.contains(extension),
        _AttachmentPickKind.file => _fileExtensions.contains(extension),
      };
      if (!supported) {
        throw StateError(
          'Định dạng .${extension.isEmpty ? '(không xác định)' : extension} '
          'chưa được hỗ trợ. Hãy chọn ảnh, video, PDF, tài liệu Office, '
          'tệp văn bản hoặc tệp nén.',
        );
      }
      final limit = switch (actualKind) {
        _AttachmentPickKind.image => _maxImageBytes,
        _AttachmentPickKind.video => _maxVideoBytes,
        _AttachmentPickKind.file => _maxFileBytes,
      };
      if (file.size <= 0) {
        throw StateError('Tệp đã chọn đang trống.');
      }
      if (file.size > limit) {
        throw StateError(
          '${_attachmentKindLabel(actualKind)} không được vượt quá '
          '${formatFileSize(limit)}.',
        );
      }

      setState(() {
        _pendingAttachment = _PendingAttachment(file: file, kind: actualKind);
      });
    } catch (error) {
      if (mounted) {
        _showError(error, fallback: 'Không thể chọn tệp đính kèm.');
      }
    }
  }

  void _removePendingAttachment() {
    if (_sending) return;
    setState(() => _pendingAttachment = null);
  }

  Future<void> _openAttachment(MessageAttachment attachment) async {
    if (attachment.isImage) {
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
                  left: 0,
                  right: 0,
                  bottom: 14,
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
      return;
    }
    final uri = Uri.tryParse(attachment.url);
    if (uri == null || !uri.hasScheme) {
      _showError(
        StateError('Đường dẫn tệp không hợp lệ.'),
        fallback: 'Không thể mở tệp.',
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showError(
        StateError('Thiết bị không có ứng dụng phù hợp để mở tệp.'),
        fallback: 'Không thể mở tệp.',
      );
    }
  }

  void _selectMessage(Message message) {
    if (message.messageType == MessageType.system || message.isRecalled) {
      return;
    }
    setState(() {
      _selectedMessageId = _selectedMessageId == message.id ? null : message.id;
    });
  }

  void _beginReply(Message message) {
    if (message.messageType == MessageType.system || message.isRecalled) {
      return;
    }
    setState(() {
      _replyingTo = message;
      _selectedMessageId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _composerFocusNode.requestFocus();
    });
  }

  void _cancelReply() {
    if (_replyingTo == null) return;
    setState(() => _replyingTo = null);
  }

  Future<void> _jumpToMessage(String messageId) async {
    if (messageId.isEmpty) return;

    var targetIndex = _messages.indexWhere(
      (message) => message.id == messageId,
    );
    while (targetIndex < 0 && _nextCursor != null) {
      final previousCount = _messages.length;
      await _loadOlder();
      if (!mounted) return;
      targetIndex = _messages.indexWhere((message) => message.id == messageId);
      if (_messages.length == previousCount) break;
    }

    if (targetIndex < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tin nhắn gốc không còn trong cuộc trò chuyện này.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _messageKeys.putIfAbsent(messageId, GlobalKey.new);
    _messageHighlightTimer?.cancel();
    setState(() {
      _selectedMessageId = null;
      _highlightedMessageId = messageId;
    });

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;

    // ListView dựng phần tử theo nhu cầu. Đưa vùng cuộn tới vị trí ước lượng
    // trước, sau đó dùng context thật để căn chính xác tin nhắn vào giữa màn hình.
    if (_messages.length > 1) {
      final estimatedOffset =
          _scrollController.position.maxScrollExtent *
          (targetIndex / (_messages.length - 1));
      _scrollController.jumpTo(
        estimatedOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    }

    for (var attempt = 0; attempt < 8; attempt += 1) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      final targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.42,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
        break;
      }

      final visibleIndexes = <int>[];
      for (final entry in _messageKeys.entries) {
        if (entry.value.currentContext == null) continue;
        final index = _messages.indexWhere(
          (message) => message.id == entry.key,
        );
        if (index >= 0) visibleIndexes.add(index);
      }
      if (visibleIndexes.isEmpty) continue;
      visibleIndexes.sort();
      final centerIndex = (visibleIndexes.first + visibleIndexes.last) / 2.0;
      final visibleCount = (visibleIndexes.last - visibleIndexes.first + 1)
          .clamp(1, _messages.length);
      final estimatedItemExtent =
          _scrollController.position.viewportDimension / visibleCount;
      final nextOffset =
          _scrollController.position.pixels +
          (targetIndex - centerIndex) * estimatedItemExtent;
      _scrollController.jumpTo(
        nextOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    }

    _messageHighlightTimer = Timer(const Duration(milliseconds: 2300), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  void _upsertMessage(Message message) {
    setState(() {
      _messages = _deduplicateAndSort([..._messages, message]);
      if (_replyingTo?.id == message.id) {
        _replyingTo = message.isRecalled ? null : message;
      }
    });
  }

  Future<void> _showMoreActions(Message message) async {
    final action = await showModalBottomSheet<_MessageMoreAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final canRecall = message.senderId == _currentUserId && !message.isCall;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canRecall)
                  ListTile(
                    leading: const Icon(Icons.undo_rounded),
                    title: const Text('Thu hồi'),
                    subtitle: const Text(
                      'Tin nhắn sẽ được thay bằng thông báo đã thu hồi',
                    ),
                    onTap: () =>
                        Navigator.pop(sheetContext, _MessageMoreAction.recall),
                  ),
                ListTile(
                  leading: const Icon(Icons.forward_rounded),
                  title: const Text('Chuyển tiếp'),
                  subtitle: const Text(
                    'Gửi tin nhắn này đến cuộc trò chuyện khác',
                  ),
                  onTap: () =>
                      Navigator.pop(sheetContext, _MessageMoreAction.forward),
                ),
                ListTile(
                  leading: Icon(
                    message.isPinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                  ),
                  title: Text(
                    message.isPinned && message.pinnedBy != _currentUserId
                        ? 'Đã được người khác ghim'
                        : message.isPinned
                        ? 'Bỏ ghim'
                        : 'Ghim tin nhắn',
                  ),
                  subtitle: Text(
                    message.isPinned && message.pinnedBy != _currentUserId
                        ? 'Chỉ người đã ghim mới có thể bỏ ghim'
                        : message.isPinned
                        ? 'Xóa tin nhắn khỏi danh sách đã ghim'
                        : 'Lưu tin nhắn vào danh sách đã ghim',
                  ),
                  enabled:
                      !message.isPinned || message.pinnedBy == _currentUserId,
                  onTap: !message.isPinned || message.pinnedBy == _currentUserId
                      ? () =>
                            Navigator.pop(sheetContext, _MessageMoreAction.pin)
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _MessageMoreAction.recall:
        await _recallMessage(message);
        break;
      case _MessageMoreAction.forward:
        await _forwardMessage(message);
        break;
      case _MessageMoreAction.pin:
        await _updateMessagePin(message);
        break;
    }
  }

  Future<void> _updateMessagePin(Message message) async {
    setState(() => _messageActionBusy.add(message.id));
    try {
      final updated = await _app.chatService.updateMessagePin(
        _conversation.id,
        message.id,
        !message.isPinned,
      );
      if (!mounted) return;
      _upsertMessage(updated);
      setState(() {
        _selectedMessageId = null;
        _pinnedMessages = updated.isPinned
            ? [
                updated,
                ..._pinnedMessages.where((item) => item.id != updated.id),
              ]
            : _pinnedMessages
                  .where((item) => item.id != updated.id)
                  .toList(growable: false);
      });
      unawaited(_loadPinnedMessages());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isPinned ? 'Đã bỏ ghim tin nhắn.' : 'Đã ghim tin nhắn.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (mounted) {
        _showError(error, fallback: 'Không thể cập nhật ghim tin nhắn.');
      }
    } finally {
      if (mounted) setState(() => _messageActionBusy.remove(message.id));
    }
  }

  Future<void> _showMessageFinder({required bool pinned}) async {
    final selected = await showModalBottomSheet<Message>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _MessageFinderSheet(
        conversationId: _conversation.id,
        pinned: pinned,
        onLoad: (query) => pinned
            ? _app.chatService.getPinnedMessages(_conversation.id)
            : _app.chatService.searchMessages(_conversation.id, query),
        senderName: _senderName,
      ),
    );
    if (!mounted || selected == null) return;
    await _jumpToMessage(selected.id);
  }

  Future<void> _recallMessage(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thu hồi tin nhắn?'),
        content: const Text(
          'Mọi người trong cuộc trò chuyện sẽ thấy tin nhắn đã được thu hồi.',
        ),
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
    if (confirmed != true || !mounted) return;

    setState(() => _messageActionBusy.add(message.id));
    try {
      final updated = await _app.chatService.recallMessage(message.id);
      if (!mounted) return;
      _upsertMessage(updated);
      unawaited(_loadPinnedMessages());
      setState(() {
        _selectedMessageId = null;
        if (_replyingTo?.id == message.id) _replyingTo = null;
        _pinnedMessages = _pinnedMessages
            .where((item) => item.id != message.id)
            .toList(growable: false);
      });
      widget.onConversationChanged?.call();
    } catch (error) {
      if (mounted) {
        _showError(error, fallback: 'Không thể thu hồi tin nhắn.');
      }
    } finally {
      if (mounted) setState(() => _messageActionBusy.remove(message.id));
    }
  }

  Future<void> _showReactionPalette(Message message) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final option in _reactionOptions)
                _ReactionOption(
                  emoji: option,
                  selected: message.hasReaction(_currentUserId, option),
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || emoji == null) return;
    await _changeReaction(message, emoji);
  }

  Future<void> _changeReaction(Message message, String emoji) async {
    if (_messageActionBusy.contains(message.id)) return;
    setState(() => _messageActionBusy.add(message.id));
    try {
      final updated = message.hasReaction(_currentUserId, emoji)
          ? await _app.chatService.removeReaction(message.id)
          : await _app.chatService.setReaction(message.id, emoji);
      if (!mounted) return;
      _upsertMessage(updated);
      setState(() => _selectedMessageId = null);
    } catch (error) {
      if (mounted) {
        _showError(error, fallback: 'Không thể cập nhật cảm xúc.');
      }
    } finally {
      if (mounted) setState(() => _messageActionBusy.remove(message.id));
    }
  }

  Future<void> _showReactionDetails(
    Message message,
    MessageReactionSummary summary,
  ) async {
    final names = summary.userIds
        .map((userId) {
          if (userId == _currentUserId) {
            final name = _app.currentUser?.preferredName.trim();
            return '${name == null || name.isEmpty ? 'Bạn' : name} (Bạn)';
          }
          return _senderName(userId);
        })
        .toList(growable: false);

    final changeReaction = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${summary.emoji} ${summary.count} người đã thả cảm xúc',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: names.length,
                itemBuilder: (_, index) {
                  final userId = summary.userIds[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ChatAvatar(
                      label: names[index],
                      imageUrl: _senderAvatar(userId),
                      radius: 20,
                    ),
                    title: Text(names[index]),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(sheetContext, true),
              icon: Text(summary.emoji),
              label: Text(
                summary.reactedByCurrentUser
                    ? 'Gỡ cảm xúc của bạn'
                    : 'Thả ${summary.emoji}',
              ),
            ),
          ],
        ),
      ),
    );
    if (changeReaction == true && mounted) {
      await _changeReaction(message, summary.emoji);
    }
  }

  Future<void> _forwardMessage(Message message) async {
    final target = await showModalBottomSheet<Conversation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ForwardConversationSheet(
        currentUserId: _currentUserId,
        loadConversations: _app.chatService.getConversations,
      ),
    );
    if (!mounted || target == null) return;

    setState(() => _messageActionBusy.add(message.id));
    try {
      final forwarded = await _app.chatService.forwardMessage(
        message.id,
        target.id,
      );
      if (!mounted) return;
      if (target.id == widget.conversation.id) {
        _upsertMessage(forwarded);
        _scrollToBottom(afterLayout: true);
      }
      setState(() => _selectedMessageId = null);
      widget.onConversationChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã chuyển tiếp đến ${target.titleFor(_currentUserId)}.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (mounted) {
        _showError(error, fallback: 'Không thể chuyển tiếp tin nhắn.');
      }
    } finally {
      if (mounted) setState(() => _messageActionBusy.remove(message.id));
    }
  }

  void _showError(Object error, {required String fallback}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: fallback)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _startCall(CallMediaType mediaType) async {
    final recipient = widget.conversation.otherParticipant(_currentUserId);
    if (recipient == null) return;

    final relationship = _relationship;
    if (relationship?.canCall != true) {
      final message = relationship?.hasBlockedMe == true
          ? 'Bạn đã bị ${recipient.displayName} chặn nên không thể gọi điện.'
          : relationship?.isBlockedByMe == true
          ? 'Bạn đã chặn ${recipient.displayName}. Hãy huỷ chặn trước khi gọi điện.'
          : 'Hai người cần kết bạn trước khi gọi điện.';
      _showError(StateError(message), fallback: message);
      return;
    }
    final call = context.read<CallController>();
    final started = await call.startCall(
      callee: CallPeer(
        id: recipient.id,
        displayName: recipient.displayName,
        avatarUrl: recipient.avatarUrl,
      ),
      conversationId: widget.conversation.id,
      mediaType: mediaType,
    );
    if (!started && mounted && !call.isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            call.socketConnected
                ? 'Không thể bắt đầu cuộc gọi.'
                : 'Đang mất kết nối tới máy chủ cuộc gọi.',
          ),
        ),
      );
    }
  }

  Future<void> _startGroupCall(CallMediaType mediaType) async {
    if (_isGroupDissolved) return;
    final groupCall = context.read<GroupCallController>();
    final directCall = context.read<CallController>();
    if (directCall.isBusy || !groupCall.canStart) return;
    final started = await groupCall.start(
      conversationId: _conversation.id,
      name: _conversation.titleFor(_currentUserId),
      mediaType: mediaType,
    );
    if (!started && mounted) {
      _showError(
        StateError('Không thể bắt đầu cuộc gọi nhóm.'),
        fallback: 'Không thể bắt đầu cuộc gọi nhóm.',
      );
    }
  }

  Future<void> _showUserProfile(Participant participant) {
    if (participant.id == _currentUserId) return Future.value();
    return showUserQuickProfileSheet(
      context,
      participant: participant,
      chatService: _app.chatService,
      friendService: _app.friendService,
      userService: _app.userService,
      onMessage: () => _openPrivateChat(participant),
      onAudioCall: () => _startPrivateCall(participant, CallMediaType.audio),
      onVideoCall: () => _startPrivateCall(participant, CallMediaType.video),
      onRelationshipChanged: _loadRelationship,
    );
  }

  Future<void> _showGroupInfo() async {
    var latestConversation = _conversation;
    try {
      final conversations = await _app.chatService.getConversations();
      latestConversation = conversations.firstWhere(
        (conversation) => conversation.id == widget.conversation.id,
        orElse: () => _conversation,
      );
    } catch (_) {
      // The cached conversation still provides a usable information sheet.
    }
    if (!mounted) return;
    final left = await showConversationInfoSheet(
      context,
      conversation: latestConversation,
      currentUserId: _currentUserId,
      currentUser: _app.currentUser,
      onParticipantTap: _showUserProfile,
    );
    if (left == true && mounted) {
      widget.onConversationChanged?.call();
      Navigator.of(context).pop();
    }
  }

  Future<Conversation> _directConversationFor(Participant participant) async {
    if (widget.conversation.isDirect &&
        widget.conversation.participants.any(
          (member) => member.id == participant.id,
        )) {
      return widget.conversation;
    }
    return _app.chatService.createDirectConversation(participant.id);
  }

  Future<void> _openPrivateChat(Participant participant) async {
    try {
      final conversation = await _directConversationFor(participant);
      if (!mounted || conversation.id == widget.conversation.id) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversation: conversation,
            onConversationChanged: widget.onConversationChanged,
          ),
        ),
      );
    } catch (error) {
      if (mounted) _showError(error, fallback: 'Không thể mở đoạn chat riêng.');
    }
  }

  Future<void> _startPrivateCall(
    Participant participant,
    CallMediaType mediaType,
  ) async {
    try {
      final conversation = await _directConversationFor(participant);
      if (!mounted) return;
      final call = context.read<CallController>();
      final started = await call.startCall(
        callee: CallPeer(
          id: participant.id,
          displayName: participant.displayName,
          avatarUrl: participant.avatarUrl,
        ),
        conversationId: conversation.id,
        mediaType: mediaType,
      );
      if (!started && mounted && !call.isBusy) {
        _showError(
          StateError('Không thể bắt đầu cuộc gọi.'),
          fallback: 'Không thể bắt đầu cuộc gọi.',
        );
      }
    } catch (error) {
      if (mounted) _showError(error, fallback: 'Không thể bắt đầu cuộc gọi.');
    }
  }

  String _pinnedMessagePreview(Message message) {
    final attachment = message.attachment;
    if (attachment != null) {
      final label = attachment.isImage
          ? '📷 Ảnh'
          : attachment.isVideo
          ? '🎬 Video'
          : '📎 ${attachment.fileName}';
      return message.content.trim().isEmpty
          ? label
          : '$label · ${message.content.trim()}';
    }
    if (message.isCall) return '📞 Lịch sử cuộc gọi';
    return message.content.trim().isEmpty ? 'Tin nhắn' : message.content.trim();
  }

  Widget _buildPinnedMessageBanner() {
    if (_pinnedMessages.isEmpty) return const SizedBox.shrink();
    final message = _pinnedMessages.first;
    final remaining = _pinnedMessages.length - 1;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Material(
        color: colors.surface,
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, color: colors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => unawaited(_jumpToMessage(message.id)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tin nhắn',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${_senderName(message.senderId)}: ${_pinnedMessagePreview(message)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                  side: BorderSide(color: colors.outline),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => unawaited(_showMessageFinder(pinned: true)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 68,
                      minHeight: 34,
                      maxWidth: 96,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Center(
                        child: Text(
                          remaining > 0 ? '+$remaining ghim' : '1 ghim',
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (message.pinnedBy == _currentUserId)
                PopupMenuButton<String>(
                  tooltip: 'Tùy chọn tin nhắn đã ghim',
                  onSelected: (value) {
                    if (value == 'unpin') unawaited(_updateMessagePin(message));
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'unpin',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.push_pin_outlined),
                        title: Text('Bỏ ghim tin nhắn này'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentConversation = _conversation;
    final title = currentConversation.titleFor(_currentUserId);
    final otherParticipant = currentConversation.isDirect
        ? currentConversation.otherParticipant(_currentUserId)
        : null;
    final presenceController = context.watch<CallController>();
    final otherOnline =
        otherParticipant != null &&
        presenceController.isUserOnline(otherParticipant.id);
    final otherLastSeen = otherParticipant == null
        ? null
        : presenceController.recentlyOfflineAt(otherParticipant.id) ??
              otherParticipant.lastSeenAt;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (otherParticipant != null) {
              unawaited(_showUserProfile(otherParticipant));
              return;
            }
            unawaited(_showGroupInfo());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                ChatAvatar(
                  label: title,
                  imageUrl: currentConversation.avatarUrlFor(_currentUserId),
                  radius: 19,
                  isGroup: widget.conversation.isGroup,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                          ),
                        ],
                      ),
                      Text(
                        currentConversation.isGroup
                            ? currentConversation.group?.isDissolved == true
                                  ? 'Nhóm đã bị giải tán'
                                  : '${currentConversation.participants.length} thành viên'
                            : presenceText(
                                isOnline: otherOnline,
                                lastSeenAt: otherLastSeen,
                                presenceVisible:
                                    otherParticipant?.presenceVisible ?? true,
                              ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Tìm kiếm tin nhắn',
            onPressed: () => unawaited(_showMessageFinder(pinned: false)),
            icon: const Icon(Icons.search_rounded),
          ),
          if (currentConversation.isDirect)
            Consumer<CallController>(
              builder: (context, call, _) => IconButton(
                tooltip: call.socketConnected
                    ? 'Gọi thoại'
                    : 'Đang kết nối cuộc gọi',
                onPressed: call.canStartCall && _relationship?.canCall == true
                    ? () => _startCall(CallMediaType.audio)
                    : null,
                icon: const Icon(Icons.call_outlined),
              ),
            ),
          if (currentConversation.isGroup && !_isGroupDissolved)
            Consumer2<GroupCallController, CallController>(
              builder: (context, groupCall, directCall, _) {
                final canRejoin = groupCall.canRejoin(currentConversation.id);
                final activeType =
                    groupCall.availableMediaType ?? CallMediaType.audio;
                final activeCount = groupCall.availableParticipantCount;

                Widget actionIcon({required bool video}) {
                  final isActiveAction =
                      canRejoin && activeType.isVideo == video;
                  final icon = Icon(
                    video
                        ? (isActiveAction
                              ? Icons.video_call_rounded
                              : Icons.video_call_outlined)
                        : (isActiveAction
                              ? Icons.call_rounded
                              : Icons.call_outlined),
                  );

                  if (!isActiveAction) return icon;
                  return Badge(
                    label: Text('$activeCount'),
                    backgroundColor: Colors.green,
                    child: icon,
                  );
                }

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: canRejoin && !activeType.isVideo
                          ? 'Vào lại cuộc gọi thoại ($activeCount người)'
                          : 'Gọi thoại nhóm',
                      color: canRejoin && !activeType.isVideo
                          ? Colors.green
                          : null,
                      onPressed:
                          groupCall.canStart &&
                              !directCall.isBusy &&
                              (!canRejoin || !activeType.isVideo)
                          ? () => _startGroupCall(CallMediaType.audio)
                          : null,
                      icon: actionIcon(video: false),
                    ),
                    IconButton(
                      tooltip: canRejoin && activeType.isVideo
                          ? 'Vào lại cuộc gọi video ($activeCount người)'
                          : 'Gọi video nhóm',
                      color: canRejoin && activeType.isVideo
                          ? Colors.green
                          : null,
                      onPressed:
                          groupCall.canStart &&
                              !directCall.isBusy &&
                              (!canRejoin || activeType.isVideo)
                          ? () => _startGroupCall(CallMediaType.video)
                          : null,
                      icon: actionIcon(video: true),
                    ),
                  ],
                );
              },
            ),
          if (currentConversation.isDirect)
            Consumer<CallController>(
              builder: (context, call, _) => IconButton(
                tooltip: call.socketConnected
                    ? 'Gọi video'
                    : 'Đang kết nối cuộc gọi',
                onPressed: call.canStartCall && _relationship?.canCall == true
                    ? () => _startCall(CallMediaType.video)
                    : null,
                icon: const Icon(Icons.videocam_outlined),
              ),
            ),
          if (_syncFailed)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Mất kết nối, ứng dụng sẽ tự thử lại',
                child: Icon(Icons.cloud_off_rounded, size: 20),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildPinnedMessageBanner(),
            Expanded(
              child: ColoredBox(
                color: _chatBackgroundColor(context),
                child: _buildMessages(),
              ),
            ),
            if (currentConversation.isDirect &&
                _relationship != null &&
                (!_relationship!.isFriend || _relationship!.isBlocked))
              _MessageRequestBanner(
                relationship: _relationship!,
                otherName: currentConversation.titleFor(_currentUserId),
                pending: _relationshipPending,
                onAccept: _acceptMessageRequest,
                onBlock: _blockMessageRequester,
              ),
            if (_isGroupDissolved)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 19,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Nhóm đã bị giải tán. Bạn không thể nhắn tin hoặc gọi điện.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              _MessageComposer(
                controller: _composerController,
                focusNode: _composerFocusNode,
                sending: _sending,
                interactionEnabled:
                    !currentConversation.isDirect ||
                    _relationship?.canSendMessage == true,
                canSend:
                    _composerController.text.trim().isNotEmpty ||
                    _pendingAttachment != null,
                pendingAttachment: _pendingAttachment,
                uploadProgress: _uploadProgress,
                replyingTo: _replyingTo,
                replySenderName: _replyingTo == null
                    ? null
                    : _replyingTo!.senderId == _currentUserId
                    ? 'Bạn'
                    : _senderName(_replyingTo!.senderId),
                onCancelReply: _cancelReply,
                onPickAttachment: _pickAttachment,
                onRemoveAttachment: _removePendingAttachment,
                onSend: _sendMessage,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_initialError != null && _messages.isEmpty) {
      return ChatErrorView(message: _initialError!, onRetry: _loadInitial);
    }

    if (_messages.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadInitial,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 96),
            const Icon(Icons.waving_hand_rounded, size: 60, color: flowPink),
            const SizedBox(height: 18),
            Text(
              'Hãy gửi lời chào đầu tiên!',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
        itemCount: _messages.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: _loadingOlder
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    )
                  : _nextCursor == null
                  ? const SizedBox(height: 6)
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          'Cuộn lên để xem tin nhắn cũ hơn',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
            );
          }

          final messageIndex = index - 1;
          final message = _messages[messageIndex];
          final previousMessage = messageIndex == 0
              ? null
              : _messages[messageIndex - 1];
          final showDate =
              previousMessage == null ||
              !_sameDay(previousMessage.createdAt, message.createdAt);
          final showTime =
              shouldShowMessageTime(
                previousMessage?.createdAt,
                message.createdAt,
              ) ||
              showDate;
          final mine = message.isForwarded
              ? message.senderId == _currentUserId
              : message.call?.isOutgoingFor(_currentUserId) ??
                    message.senderId == _currentUserId;
          final showAvatar =
              !mine &&
              (previousMessage == null ||
                  showTime ||
                  previousMessage.senderId != message.senderId);

          final messageKey = _messageKeys.putIfAbsent(
            message.id,
            GlobalKey.new,
          );
          return AnimatedContainer(
            key: messageKey,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _highlightedMessageId == message.id
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.52)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: _highlightedMessageId == message.id
                  ? Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.55),
                      width: 1.4,
                    )
                  : null,
            ),
            child: Column(
              children: [
                if (showTime)
                  _TimeMarker(date: message.createdAt, includeDate: showDate),
                _MessageBubble(
                  message: message,
                  mine: mine,
                  senderName: _senderName(message.senderId),
                  senderAvatarUrl: _senderAvatar(message.senderId),
                  showSender: widget.conversation.isGroup,
                  showAvatar: showAvatar,
                  selected: _selectedMessageId == message.id,
                  actionBusy: _messageActionBusy.contains(message.id),
                  currentUserId: _currentUserId,
                  replySenderName: message.replyTo == null
                      ? null
                      : message.replyTo!.senderId == _currentUserId
                      ? 'Bạn'
                      : _senderName(message.replyTo!.senderId),
                  onSelect: () => _selectMessage(message),
                  onMore: () => _showMoreActions(message),
                  onReply: () => _beginReply(message),
                  onReact: () => _showReactionPalette(message),
                  onReactionTap: (summary) =>
                      _showReactionDetails(message, summary),
                  onReplyQuoteTap: message.replyTo == null
                      ? null
                      : () => _jumpToMessage(message.replyTo!.messageId),
                  onAvatarTap: () {
                    for (final participant
                        in widget.conversation.participants) {
                      if (participant.id == message.senderId) {
                        unawaited(_showUserProfile(participant));
                        break;
                      }
                    }
                  },
                  onOpenAttachment: () {
                    final attachment = message.attachment;
                    if (attachment != null) {
                      unawaited(_openAttachment(attachment));
                    }
                  },
                  onCallBack: _startCall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _senderName(String senderId) {
    for (final participant in widget.conversation.participants) {
      if (participant.id == senderId) return participant.displayName;
    }
    return 'Thành viên';
  }

  String? _senderAvatar(String senderId) {
    for (final participant in widget.conversation.participants) {
      if (participant.id == senderId) return participant.avatarUrl;
    }
    return null;
  }
}

class _MessageRequestBanner extends StatelessWidget {
  const _MessageRequestBanner({
    required this.relationship,
    required this.otherName,
    required this.pending,
    required this.onAccept,
    required this.onBlock,
  });

  final FriendRelationship relationship;
  final String otherName;
  final bool pending;
  final VoidCallback onAccept;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (relationship.isBlocked) {
      return Material(
        color: colors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Text(
            relationship.isBlockedByMe
                ? 'Bạn đã chặn $otherName. Hãy huỷ chặn trong hồ sơ để tiếp tục liên hệ.'
                : '$otherName đã chặn bạn. Hai người không thể nhắn tin hoặc gọi điện.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onErrorContainer),
          ),
        ),
      );
    }
    if (relationship.isIncomingRequest) {
      final introduction = relationship.requestMessage?.trim();
      return Material(
        color: colors.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            children: [
              if (introduction != null && introduction.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lời giới thiệu từ $otherName',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(introduction),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
              ],
              Text(
                'Chấp nhận để bạn và $otherName trở thành bạn bè, sau đó có thể nhắn tin và gọi điện cho nhau.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: pending ? null : onBlock,
                      icon: const Icon(Icons.block_rounded),
                      label: const Text('Chặn'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: pending ? null : onAccept,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Chấp nhận'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.schedule_rounded, size: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                'Đang chờ $otherName chấp nhận. Bạn có thể gửi tin nhưng chưa thể gọi.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.interactionEnabled,
    required this.canSend,
    required this.pendingAttachment,
    required this.uploadProgress,
    required this.replyingTo,
    required this.replySenderName,
    required this.onCancelReply,
    required this.onPickAttachment,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool interactionEnabled;
  final bool canSend;
  final _PendingAttachment? pendingAttachment;
  final double? uploadProgress;
  final Message? replyingTo;
  final String? replySenderName;
  final VoidCallback onCancelReply;
  final VoidCallback onPickAttachment;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.8),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.07),
              blurRadius: 14,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyingTo case final message?) ...[
                _ComposerReplyPreview(
                  message: message,
                  senderName: replySenderName ?? 'Thành viên',
                  onCancel: onCancelReply,
                ),
                const SizedBox(height: 7),
              ],
              if (pendingAttachment case final attachment?) ...[
                _PendingAttachmentPreview(
                  attachment: attachment,
                  sending: sending,
                  uploadProgress: uploadProgress,
                  onRemove: onRemoveAttachment,
                ),
                const SizedBox(height: 7),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Gửi ảnh, video hoặc tệp',
                    onPressed: sending || !interactionEnabled
                        ? null
                        : onPickAttachment,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(44),
                      foregroundColor: colors.primary,
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !sending && interactionEnabled,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'Soạn tin nhắn…',
                        filled: true,
                        fillColor: isDark
                            ? colors.surfaceContainerHighest
                            : const Color(0xFFF7F7FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(23),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(23),
                          borderSide: BorderSide(
                            color: colors.outlineVariant.withValues(
                              alpha: 0.78,
                            ),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(23),
                          borderSide: BorderSide(
                            color: colors.primary.withValues(alpha: 0.65),
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SendMessageButton(
                    sending: sending,
                    enabled: canSend && !sending && interactionEnabled,
                    onPressed: onSend,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({
    required this.attachment,
    required this.sending,
    required this.uploadProgress,
    required this.onRemove,
  });

  final _PendingAttachment attachment;
  final bool sending;
  final double? uploadProgress;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = uploadProgress;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _pickKindIcon(attachment.kind),
                  color: colors.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sending && progress != null
                          ? 'Đang tải lên ${(progress * 100).round()}%'
                          : formatFileSize(attachment.file.size),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Bỏ tệp đính kèm',
                onPressed: sending ? null : onRemove,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          if (sending && progress != null) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: progress, minHeight: 4),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComposerReplyPreview extends StatelessWidget {
  const _ComposerReplyPreview({
    required this.message,
    required this.senderName,
    required this.onCancel,
  });

  final Message message;
  final String senderName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 7, 4, 7),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang trả lời $senderName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.isRecalled
                      ? 'Tin nhắn đã được thu hồi'
                      : message.attachment != null
                      ? _attachmentMessageLabel(message.attachment!)
                      : message.content.trim().isEmpty
                      ? 'Tin nhắn'
                      : message.content.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hủy trả lời',
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _SendMessageButton extends StatelessWidget {
  const _SendMessageButton({
    required this.sending,
    required this.enabled,
    required this.onPressed,
  });

  final bool sending;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: sending ? 'Đang gửi tin nhắn' : 'Gửi tin nhắn',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? const LinearGradient(colors: [flowPurple, flowPink])
              : null,
          color: enabled ? null : colors.surfaceContainerHighest,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: flowPink.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: IconButton(
          tooltip: 'Gửi',
          onPressed: enabled ? onPressed : null,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            foregroundColor: Colors.white,
            disabledForegroundColor: colors.onSurfaceVariant.withValues(
              alpha: 0.45,
            ),
          ),
          icon: sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 21),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.senderName,
    required this.senderAvatarUrl,
    required this.showSender,
    required this.showAvatar,
    required this.selected,
    required this.actionBusy,
    required this.currentUserId,
    required this.replySenderName,
    required this.onSelect,
    required this.onMore,
    required this.onReply,
    required this.onReact,
    required this.onReactionTap,
    required this.onReplyQuoteTap,
    required this.onAvatarTap,
    required this.onOpenAttachment,
    required this.onCallBack,
  });

  final Message message;
  final bool mine;
  final String senderName;
  final String? senderAvatarUrl;
  final bool showSender;
  final bool showAvatar;
  final bool selected;
  final bool actionBusy;
  final String currentUserId;
  final String? replySenderName;
  final VoidCallback onSelect;
  final VoidCallback onMore;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final ValueChanged<MessageReactionSummary> onReactionTap;
  final VoidCallback? onReplyQuoteTap;
  final VoidCallback onAvatarTap;
  final VoidCallback onOpenAttachment;
  final Future<void> Function(CallMediaType mediaType) onCallBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = DateFormat('HH:mm').format(message.createdAt.toLocal());
    final content = message.content.trim();
    final attachment = message.attachment;

    if (message.messageType == MessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 18),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                content,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ),
      );
    }

    if (message.call case final call?) {
      final summaries = summarizeMessageReactions(
        message.reactions,
        currentUserId,
      );
      return Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: selected
                ? Padding(
                    padding: EdgeInsets.only(left: mine ? 0 : 36, bottom: 3),
                    child: _MessageActionBar(
                      busy: actionBusy,
                      onMore: onMore,
                      onReply: onReply,
                      onReact: onReact,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            onLongPress: onSelect,
            child: _CallMessageBubble(
              metadata: call,
              mine: mine,
              senderName: senderName,
              senderAvatarUrl: senderAvatarUrl,
              showAvatar: showAvatar,
              onAvatarTap: onAvatarTap,
              onCallBack: onCallBack,
            ),
          ),
          if (summaries.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: mine ? 0 : 36, top: 3),
              child: Wrap(
                alignment: mine ? WrapAlignment.end : WrapAlignment.start,
                spacing: 4,
                runSpacing: 3,
                children: [
                  for (final summary in summaries)
                    _ReactionChip(
                      summary: summary,
                      busy: actionBusy,
                      onTap: () => onReactionTap(summary),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    final recalled = message.isRecalled;
    final reply = message.replyTo;
    final outgoingColor = recalled ? colors.onSurfaceVariant : Colors.white;
    final summaries = summarizeMessageReactions(
      message.reactions,
      currentUserId,
    );

    return Semantics(
      button: !recalled,
      onTap: recalled ? null : onSelect,
      label:
          '${mine ? 'Bạn' : senderName}, $time: '
          '${recalled
              ? 'Tin nhắn đã được thu hồi'
              : attachment == null
              ? content
              : _attachmentMessageLabel(attachment)}',
      child: Padding(
        padding: EdgeInsets.only(top: showAvatar ? 5 : 2),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              child: selected
                  ? Padding(
                      padding: EdgeInsets.only(left: mine ? 0 : 36, bottom: 3),
                      child: _MessageActionBar(
                        busy: actionBusy,
                        onMore: onMore,
                        onReply: onReply,
                        onReact: onReact,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Row(
              mainAxisAlignment: mine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!mine) ...[
                  SizedBox(
                    width: 30,
                    child: showAvatar
                        ? InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onAvatarTap,
                            child: ChatAvatar(
                              label: senderName,
                              imageUrl: senderAvatarUrl,
                              radius: 14,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: recalled ? null : onSelect,
                    onLongPress: recalled ? null : onSelect,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.74,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: mine && !recalled
                            ? null
                            : Theme.of(context).brightness == Brightness.dark
                            ? colors.surfaceContainerHighest
                            : Colors.white,
                        gradient: mine && !recalled
                            ? const LinearGradient(
                                colors: [flowPurple, flowPink],
                              )
                            : null,
                        border: mine && !recalled
                            ? null
                            : Border.all(
                                color: colors.outlineVariant.withValues(
                                  alpha: 0.72,
                                ),
                              ),
                        boxShadow: mine && !recalled
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.035),
                                  blurRadius: 5,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(mine ? 16 : 5),
                          bottomRight: Radius.circular(mine ? 5 : 16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!mine && showSender && showAvatar) ...[
                            Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 3),
                          ],
                          if (!recalled && message.isPinned) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 13,
                                  color: mine ? Colors.white70 : colors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Đã ghim',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: mine
                                            ? Colors.white70
                                            : colors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (!recalled && message.isForwarded) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.forward_rounded,
                                  size: 14,
                                  color: mine ? Colors.white70 : colors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Đã chuyển tiếp',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: mine
                                            ? Colors.white70
                                            : colors.primary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (!recalled && reply != null) ...[
                            _ReplyQuote(
                              reply: reply,
                              senderName: replySenderName ?? 'Thành viên',
                              mine: mine,
                              onTap: onReplyQuoteTap,
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (recalled)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.block_rounded,
                                  size: 16,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Tin nhắn đã được thu hồi',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                          fontStyle: FontStyle.italic,
                                          height: 1.32,
                                        ),
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            if (attachment != null)
                              _AttachmentMessageContent(
                                attachment: attachment,
                                mine: mine,
                                onOpen: onOpenAttachment,
                              ),
                            if (attachment != null && content.isNotEmpty)
                              const SizedBox(height: 7),
                            if (content.isNotEmpty || attachment == null)
                              Text(
                                content.isEmpty ? 'Tin nhắn' : content,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: mine
                                          ? outgoingColor
                                          : colors.onSurface,
                                      height: 1.32,
                                    ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (!recalled && summaries.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(left: mine ? 0 : 36, top: 3),
                child: Wrap(
                  alignment: mine ? WrapAlignment.end : WrapAlignment.start,
                  spacing: 4,
                  runSpacing: 3,
                  children: [
                    for (final summary in summaries)
                      _ReactionChip(
                        summary: summary,
                        busy: actionBusy,
                        onTap: () => onReactionTap(summary),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentMessageContent extends StatelessWidget {
  const _AttachmentMessageContent({
    required this.attachment,
    required this.mine,
    required this.onOpen,
  });

  final MessageAttachment attachment;
  final bool mine;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (attachment.isImage) {
      return Semantics(
        button: true,
        label: 'Mở ảnh ${attachment.fileName}',
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(11),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 180,
                maxWidth: 260,
                minHeight: 120,
                maxHeight: 280,
              ),
              child: Image.network(
                attachment.url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  final total = progress.expectedTotalBytes;
                  return SizedBox(
                    width: 220,
                    height: 170,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        value: total == null
                            ? null
                            : progress.cumulativeBytesLoaded / total,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, _, _) => SizedBox(
                  width: 220,
                  height: 140,
                  child: _AttachmentLoadError(
                    label: 'Không thể tải ảnh',
                    mine: mine,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final isVideo = attachment.isVideo;
    final foreground = mine ? Colors.white : colors.onSurface;
    final secondary = mine ? Colors.white70 : colors.onSurfaceVariant;
    return Material(
      color: mine
          ? Colors.white.withValues(alpha: 0.13)
          : colors.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 215, maxWidth: 270),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: mine
                        ? Colors.white.withValues(alpha: 0.18)
                        : colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isVideo
                        ? Icons.play_circle_fill_rounded
                        : _fileIcon(attachment.fileName),
                    color: mine ? Colors.white : colors.primary,
                    size: isVideo ? 29 : 25,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${isVideo ? 'Video' : 'Tệp'} · ${formatFileSize(attachment.sizeBytes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: secondary),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVideo
                                ? Icons.open_in_new_rounded
                                : Icons.download_rounded,
                            size: 15,
                            color: secondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              isVideo ? 'Mở video' : 'Mở / tải xuống',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: secondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentLoadError extends StatelessWidget {
  const _AttachmentLoadError({required this.label, required this.mine});

  final String label;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.08),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: mine ? Colors.white70 : null,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: mine ? Colors.white70 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageActionBar extends StatelessWidget {
  const _MessageActionBar({
    required this.busy,
    required this.onMore,
    required this.onReply,
    required this.onReact,
  });

  final bool busy;
  final VoidCallback onMore;
  final VoidCallback onReply;
  final VoidCallback onReact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.inverseSurface,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: busy
            ? const SizedBox(
                width: 92,
                height: 34,
                child: Center(
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CompactActionButton(
                    tooltip: 'Hành động khác',
                    icon: Icons.more_vert_rounded,
                    onPressed: onMore,
                  ),
                  _CompactActionButton(
                    tooltip: 'Trả lời',
                    icon: Icons.reply_rounded,
                    onPressed: onReply,
                  ),
                  _CompactActionButton(
                    tooltip: 'Thả cảm xúc',
                    icon: Icons.sentiment_satisfied_alt_outlined,
                    onPressed: onReact,
                  ),
                ],
              ),
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 34),
      padding: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.onInverseSurface,
      icon: Icon(icon, size: 19),
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.reply,
    required this.senderName,
    required this.mine,
    required this.onTap,
  });

  final ReplyMessageMetadata reply;
  final String senderName;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = mine ? Colors.white : colors.onSurface;
    final secondary = mine ? Colors.white70 : colors.onSurfaceVariant;
    final text = reply.isRecalled
        ? 'Tin nhắn đã được thu hồi'
        : reply.messageType == MessageType.call
        ? 'Cuộc gọi FlowChat'
        : reply.attachment != null
        ? replyAttachmentLabel(reply.attachment!)
        : reply.content.trim().isEmpty
        ? 'Tin nhắn'
        : reply.content.trim();

    return Semantics(
      button: true,
      label: 'Đi tới tin nhắn gốc của $senderName',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(9, 6, 8, 6),
          decoration: BoxDecoration(
            color: mine
                ? Colors.white.withValues(alpha: 0.16)
                : colors.primaryContainer.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(9),
            border: Border(left: BorderSide(color: foreground, width: 2.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontStyle: reply.isRecalled ? FontStyle.italic : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.summary,
    required this.busy,
    required this.onTap,
  });

  final MessageReactionSummary summary;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: summary.reactedByCurrentUser
          ? colors.primaryContainer
          : colors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: summary.reactedByCurrentUser
              ? colors.primary.withValues(alpha: 0.55)
              : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(
            '${summary.emoji} ${summary.count}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSurface,
              fontWeight: summary.reactedByCurrentUser
                  ? FontWeight.w800
                  : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionOption extends StatelessWidget {
  const _ReactionOption({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 46,
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 26)),
          ),
        ),
      ),
    );
  }
}

class _CallMessageBubble extends StatelessWidget {
  const _CallMessageBubble({
    required this.metadata,
    required this.mine,
    required this.senderName,
    required this.senderAvatarUrl,
    required this.showAvatar,
    required this.onAvatarTap,
    required this.onCallBack,
  });

  final CallMessageMetadata metadata;
  final bool mine;
  final String senderName;
  final String? senderAvatarUrl;
  final bool showAvatar;
  final VoidCallback onAvatarTap;
  final Future<void> Function(CallMediaType mediaType) onCallBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mediaLabel = metadata.mediaType.isVideo ? 'video' : 'thoại';
    final directionLabel = mine ? 'đi' : 'đến';
    final title = 'Cuộc gọi $mediaLabel $directionLabel';
    final result = _callResultLabel(metadata, mine);
    final isMissed =
        !mine &&
        (metadata.reason == 'no-answer' || metadata.reason == 'canceled');
    final icon = isMissed
        ? Icons.phone_missed_rounded
        : metadata.mediaType.isVideo
        ? Icons.videocam_rounded
        : Icons.phone_in_talk_rounded;
    final iconColor = isMissed ? colors.error : colors.primary;

    return Semantics(
      label: '$title, $result',
      child: Padding(
        padding: EdgeInsets.only(top: showAvatar ? 6 : 3),
        child: Row(
          mainAxisAlignment: mine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              SizedBox(
                width: 30,
                child: showAvatar
                    ? InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onAvatarTap,
                        child: ChatAvatar(
                          label: senderName,
                          imageUrl: senderAvatarUrl,
                          radius: 14,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.76,
                  minWidth: 218,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? colors.surfaceContainerHigh
                      : Colors.white,
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.27),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.055),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: iconColor.withValues(alpha: 0.13),
                            ),
                            child: Icon(icon, size: 20, color: iconColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  result,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        fontWeight: FontWeight.w400,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!metadata.isGroup) ...[
                      Divider(
                        height: 1,
                        color: colors.primary.withValues(alpha: 0.16),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                        child: Consumer<CallController>(
                          builder: (context, call, _) {
                            return SizedBox(
                              height: 34,
                              child: OutlinedButton.icon(
                                onPressed: call.canStartCall
                                    ? () => onCallBack(metadata.mediaType)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 34),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  side: BorderSide(
                                    color: colors.primary.withValues(
                                      alpha: 0.34,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: Icon(
                                  metadata.mediaType.isVideo
                                      ? Icons.video_call_rounded
                                      : Icons.call_rounded,
                                  size: 18,
                                ),
                                label: const Text('Gọi lại'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageFinderSheet extends StatefulWidget {
  const _MessageFinderSheet({
    required this.conversationId,
    required this.pinned,
    required this.onLoad,
    required this.senderName,
  });

  final String conversationId;
  final bool pinned;
  final Future<List<Message>> Function(String query) onLoad;
  final String Function(String userId) senderName;

  @override
  State<_MessageFinderSheet> createState() => _MessageFinderSheetState();
}

class _MessageFinderSheetState extends State<_MessageFinderSheet> {
  final _controller = TextEditingController();
  List<Message> _results = const [];
  bool _loading = false;
  String? _error;
  CallController? _callController;
  int _handledPinRevision = 0;

  @override
  void initState() {
    super.initState();
    if (widget.pinned) unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.pinned) return;
    final callController = context.read<CallController>();
    if (identical(callController, _callController)) return;
    _callController?.removeListener(_handlePinUpdate);
    _callController = callController;
    _handledPinRevision = callController.messagePinRevision;
    callController.addListener(_handlePinUpdate);
  }

  void _handlePinUpdate() {
    final callController = _callController;
    if (!mounted || callController == null) return;
    if (callController.messagePinRevision <= _handledPinRevision) return;
    _handledPinRevision = callController.messagePinRevision;
    if (callController.messagePinConversationId == widget.conversationId) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _callController?.removeListener(_handlePinUpdate);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final query = _controller.text.trim();
    if (!widget.pinned && query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await widget.onLoad(query);
      if (!mounted) return;
      setState(() => _results = messages);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Không thể tải danh sách tin nhắn.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _preview(Message message) {
    final attachment = message.attachment;
    if (attachment != null) {
      final label = attachment.isImage
          ? '📷 Ảnh'
          : attachment.isVideo
          ? '🎬 Video'
          : '📎 ${attachment.fileName}';
      return message.content.trim().isEmpty
          ? label
          : '$label · ${message.content.trim()}';
    }
    if (message.isCall) return '📞 Lịch sử cuộc gọi';
    return message.content.trim().isEmpty ? 'Tin nhắn' : message.content.trim();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .76,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Icon(
                  widget.pinned ? Icons.push_pin_rounded : Icons.search_rounded,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.pinned ? 'Tin nhắn đã ghim' : 'Tìm kiếm tin nhắn',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.pinned)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(_load()),
                decoration: InputDecoration(
                  hintText: 'Nhập nội dung hoặc tên tệp...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    onPressed: _loading ? null : () => unawaited(_load()),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _results.isEmpty
                ? Center(
                    child: Text(
                      widget.pinned
                          ? 'Chưa có tin nhắn nào được ghim.'
                          : _controller.text.trim().isEmpty
                          ? 'Nhập từ khóa để tìm kiếm.'
                          : 'Không tìm thấy tin nhắn phù hợp.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final message = _results[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        leading: const Icon(Icons.chat_bubble_outline_rounded),
                        title: Text(
                          widget.senderName(message.senderId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _preview(message),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          DateFormat('dd/MM HH:mm').format(message.createdAt),
                          style: Theme.of(context).textTheme.labelSmall,
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
}

enum _MessageMoreAction { recall, forward, pin }

enum _AttachmentPickKind { image, video, file }

class _PendingAttachment {
  const _PendingAttachment({required this.file, required this.kind});

  final PlatformFile file;
  final _AttachmentPickKind kind;
}

_AttachmentPickKind _attachmentKindFor(
  PlatformFile file, {
  required _AttachmentPickKind fallback,
}) {
  if (fallback != _AttachmentPickKind.file) return fallback;
  final extension = (file.extension ?? _extensionOf(file.name)).toLowerCase();
  if (_imageExtensions.contains(extension)) return _AttachmentPickKind.image;
  if (_videoExtensions.contains(extension)) return _AttachmentPickKind.video;
  return _AttachmentPickKind.file;
}

String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 || dot == fileName.length - 1
      ? ''
      : fileName.substring(dot + 1);
}

const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
};

const _videoExtensions = {
  'mp4',
  'mov',
  'm4v',
  'webm',
  'avi',
  'mkv',
  '3gp',
  '3g2',
  'mpeg',
  'mpg',
};

const _fileExtensions = {
  'pdf',
  'txt',
  'csv',
  'rtf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'odt',
  'ods',
  'odp',
  'zip',
  'rar',
  '7z',
};

String _attachmentKindLabel(_AttachmentPickKind kind) {
  return switch (kind) {
    _AttachmentPickKind.image => 'Ảnh',
    _AttachmentPickKind.video => 'Video',
    _AttachmentPickKind.file => 'Tệp',
  };
}

IconData _pickKindIcon(_AttachmentPickKind kind) {
  return switch (kind) {
    _AttachmentPickKind.image => Icons.image_rounded,
    _AttachmentPickKind.video => Icons.video_file_rounded,
    _AttachmentPickKind.file => Icons.insert_drive_file_rounded,
  };
}

IconData _fileIcon(String fileName) {
  return switch (_extensionOf(fileName).toLowerCase()) {
    'pdf' => Icons.picture_as_pdf_rounded,
    'doc' || 'docx' => Icons.description_rounded,
    'xls' || 'xlsx' || 'csv' => Icons.table_chart_rounded,
    'ppt' || 'pptx' => Icons.slideshow_rounded,
    'zip' || 'rar' || '7z' => Icons.folder_zip_rounded,
    'mp3' || 'wav' || 'm4a' || 'aac' => Icons.audio_file_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}

String _attachmentMessageLabel(MessageAttachment attachment) {
  return switch (attachment.kind) {
    MessageAttachmentKind.image => 'Hình ảnh',
    MessageAttachmentKind.video =>
      'Video${attachment.fileName.isEmpty ? '' : ': ${attachment.fileName}'}',
    MessageAttachmentKind.file => attachment.fileName,
  };
}

class _ForwardConversationSheet extends StatefulWidget {
  const _ForwardConversationSheet({
    required this.currentUserId,
    required this.loadConversations,
  });

  final String currentUserId;
  final Future<List<Conversation>> Function() loadConversations;

  @override
  State<_ForwardConversationSheet> createState() =>
      _ForwardConversationSheetState();
}

class _ForwardConversationSheetState extends State<_ForwardConversationSheet> {
  final _searchController = TextEditingController();
  List<Conversation> _conversations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshSearch);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations = [...await widget.loadConversations()]
        ..sort((left, right) {
          final leftDate = left.lastMessageAt ?? DateTime(1970);
          final rightDate = right.lastMessageAt ?? DateTime(1970);
          return rightDate.compareTo(leftDate);
        });
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(
          error,
          fallback: 'Không thể tải danh sách trò chuyện.',
        );
      });
    }
  }

  List<Conversation> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _conversations;
    return _conversations
        .where((conversation) {
          return conversation
              .titleFor(widget.currentUserId)
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Chuyển tiếp đến',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm cuộc trò chuyện',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xóa tìm kiếm',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: colors.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error case final error?) {
      return ChatErrorView(message: error, onRetry: _load);
    }

    final conversations = _filtered;
    if (conversations.isEmpty) {
      return const Center(child: Text('Không tìm thấy cuộc trò chuyện.'));
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 22),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        final title = conversation.titleFor(widget.currentUserId);
        return ListTile(
          leading: ChatAvatar(
            label: title,
            imageUrl: conversation.avatarUrlFor(widget.currentUserId),
            radius: 21,
            isGroup: conversation.isGroup,
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            conversation.isGroup ? 'Nhóm chat' : 'Tin nhắn trực tiếp',
          ),
          trailing: const Icon(Icons.send_rounded, size: 20),
          onTap: () => Navigator.pop(context, conversation),
        );
      },
    );
  }
}

String _callResultLabel(CallMessageMetadata metadata, bool isOutgoing) {
  final duration = formatCallDuration(metadata.durationSeconds);
  final result = switch (metadata.reason) {
    'declined' => isOutgoing ? 'Người nhận đã từ chối' : 'Bạn đã từ chối',
    'canceled' => isOutgoing ? 'Bạn đã hủy cuộc gọi' : 'Cuộc gọi nhỡ',
    'no-answer' => isOutgoing ? 'Không có người trả lời' : 'Cuộc gọi nhỡ',
    'busy' => 'Người nhận đang bận',
    'media-error' => 'Không thể sử dụng camera/micrô',
    'connection-failed' || 'disconnected' => 'Cuộc gọi bị gián đoạn',
    'answered-elsewhere' => 'Đã trả lời trên thiết bị khác',
    _ => null,
  };
  return result == null ? duration : '$result · $duration';
}

class _TimeMarker extends StatelessWidget {
  const _TimeMarker({required this.date, required this.includeDate});

  final DateTime date;
  final bool includeDate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 5, 0, 3),
      child: Center(
        child: Text(
          _messageTimeLabel(date, includeDate: includeDate),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

DateTime _messageDate(Message message) {
  return message.createdAt;
}

bool _sameDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _messageTimeLabel(DateTime date, {required bool includeDate}) {
  final local = date.toLocal();
  final time = DateFormat('HH:mm').format(local);
  if (!includeDate) return time;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final valueDay = DateTime(local.year, local.month, local.day);
  final days = today.difference(valueDay).inDays;
  if (days == 0) return time;
  if (days == 1) return 'Hôm qua $time';
  return '${DateFormat('d/M').format(local)} $time';
}

Color _chatBackgroundColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF20222D)
      : const Color(0xFFF0F4F9);
}
