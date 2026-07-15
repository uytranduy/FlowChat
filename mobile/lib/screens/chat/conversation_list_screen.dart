import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../state/app_controller.dart';
import '../../state/call_controller.dart';
import 'chat_screen.dart';
import 'chat_widgets.dart';
import 'new_conversation_screen.dart';

typedef UnreadCountChanged = void Function(int totalUnread, int newlyUnread);

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key, this.onUnreadCountChanged});

  final UnreadCountChanged? onUnreadCountChanged;

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen>
    with WidgetsBindingObserver {
  static const _pollInterval = Duration(seconds: 5);

  final _searchController = TextEditingController();
  List<Conversation> _conversations = const [];
  Timer? _pollTimer;
  bool _initialized = false;
  bool _loading = true;
  bool _requestInFlight = false;
  bool _pollFailed = false;
  Map<String, int>? _lastUnreadByConversation;
  String? _error;
  CallController? _callController;
  int _handledConversationRevision = 0;

  AppController get _app => context.read<AppController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final callController = context.read<CallController>();
    if (!identical(_callController, callController)) {
      _callController?.removeListener(_handleConversationSignal);
      _callController = callController;
      _handledConversationRevision = callController.conversationRevision;
      callController.addListener(_handleConversationSignal);
    }
    if (_initialized) return;
    _initialized = true;
    unawaited(_loadConversations(showLoading: true));
    _startPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startPolling();
        unawaited(_loadConversations());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _pollTimer?.cancel();
        _pollTimer = null;
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _callController?.removeListener(_handleConversationSignal);
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleConversationSignal() {
    final controller = _callController;
    if (!mounted || controller == null) return;
    if (controller.conversationRevision <= _handledConversationRevision) return;
    _handledConversationRevision = controller.conversationRevision;
    unawaited(_loadConversations());
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => unawaited(_loadConversations(fromPolling: true)),
    );
  }

  Future<void> _loadConversations({
    bool showLoading = false,
    bool fromPolling = false,
  }) async {
    if (_requestInFlight) return;
    _requestInFlight = true;

    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await _app.chatService.getConversations();
      final byId = <String, Conversation>{
        for (final conversation in result) conversation.id: conversation,
      };
      final conversations = byId.values.toList()
        ..sort((a, b) => _sortDate(b).compareTo(_sortDate(a)));
      final currentUserId = _app.currentUser?.id ?? '';
      final unreadTotal = conversations.fold<int>(
        0,
        (total, conversation) =>
            total + conversation.unreadCountFor(currentUserId),
      );
      final unreadByConversation = <String, int>{
        for (final conversation in conversations)
          conversation.id: conversation.unreadCountFor(currentUserId),
      };
      final previousUnread = _lastUnreadByConversation;
      final newlyUnread = countNewUnread(previousUnread, unreadByConversation);
      _lastUnreadByConversation = unreadByConversation;

      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _loading = false;
        _error = null;
        _pollFailed = false;
      });
      widget.onUnreadCountChanged?.call(unreadTotal, newlyUnread);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _pollFailed = fromPolling;
        if (!fromPolling || _conversations.isEmpty) {
          _error = friendlyError(
            error,
            fallback: 'Không thể tải danh sách trò chuyện.',
          );
        }
      });
    } finally {
      _requestInFlight = false;
    }
  }

  DateTime _sortDate(Conversation conversation) {
    return conversation.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<Conversation> get _filteredConversations {
    final currentUserId = _app.currentUser?.id ?? '';
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _conversations;

    return _conversations.where((conversation) {
      final title = conversation.titleFor(currentUserId).toLowerCase();
      final preview =
          conversation.lastMessage?.previewFor(currentUserId).toLowerCase() ??
          '';
      return title.contains(query) || preview.contains(query);
    }).toList();
  }

  void _upsertConversation(Conversation conversation) {
    final byId = <String, Conversation>{
      for (final item in _conversations) item.id: item,
      conversation.id: conversation,
    };
    final updated = byId.values.toList()
      ..sort((a, b) => _sortDate(b).compareTo(_sortDate(a)));
    setState(() => _conversations = updated);
  }

  Future<void> _openConversation(Conversation conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversation: conversation,
          onConversationChanged: () => unawaited(_loadConversations()),
        ),
      ),
    );
    if (mounted) unawaited(_loadConversations());
  }

  Future<void> _chooseConversationType() async {
    final mode = await showModalBottomSheet<NewConversationMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bắt đầu trò chuyện',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _NewChatOption(
                icon: Icons.person_rounded,
                title: 'Tin nhắn trực tiếp',
                subtitle: 'Chọn một người bạn để trò chuyện',
                onTap: () =>
                    Navigator.pop(sheetContext, NewConversationMode.direct),
              ),
              _NewChatOption(
                icon: Icons.groups_rounded,
                title: 'Nhóm mới',
                subtitle: 'Đặt tên và chọn nhiều thành viên',
                onTap: () =>
                    Navigator.pop(sheetContext, NewConversationMode.group),
              ),
            ],
          ),
        ),
      ),
    );

    if (mode == null || !mounted) return;
    final created = await Navigator.of(context).push<Conversation>(
      MaterialPageRoute(builder: (_) => NewConversationScreen(mode: mode)),
    );

    if (created == null || !mounted) return;
    _upsertConversation(created);
    await _openConversation(created);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final conversations = _filteredConversations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tin nhắn'),
        actions: [
          if (_pollFailed)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Đang chờ kết nối lại',
                child: Icon(Icons.cloud_off_rounded, size: 20),
              ),
            ),
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _requestInFlight ? null : () => _loadConversations(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
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
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _buildBody(conversations),
            ),
          ),
        ],
      ),
      floatingActionButton: FlowGradient(
        borderRadius: BorderRadius.circular(18),
        child: FloatingActionButton.extended(
          heroTag: 'new-conversation',
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          onPressed: _chooseConversationType,
          tooltip: 'Tạo cuộc trò chuyện',
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Trò chuyện mới'),
        ),
      ),
    );
  }

  Widget _buildBody(List<Conversation> conversations) {
    if (_loading && _conversations.isEmpty) {
      return const Center(
        key: ValueKey('conversation-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null && _conversations.isEmpty) {
      return RefreshIndicator(
        key: const ValueKey('conversation-error'),
        onRefresh: () => _loadConversations(showLoading: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.55,
              child: ChatErrorView(
                message: _error!,
                onRetry: () => _loadConversations(showLoading: true),
              ),
            ),
          ],
        ),
      );
    }

    if (conversations.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return RefreshIndicator(
        key: ValueKey(
          searching ? 'conversation-no-result' : 'conversation-empty',
        ),
        onRefresh: _loadConversations,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 88),
            Icon(
              searching ? Icons.search_off_rounded : Icons.forum_outlined,
              size: 68,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              searching
                  ? 'Không tìm thấy cuộc trò chuyện phù hợp.'
                  : 'Chưa có cuộc trò chuyện nào.\nHãy bắt đầu với một người bạn nhé!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      key: const ValueKey('conversation-list'),
      onRefresh: _loadConversations,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 104),
        itemCount: conversations.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) => _ConversationCard(
          conversation: conversations[index],
          currentUserId: _app.currentUser?.id ?? '',
          onTap: () => _openConversation(conversations[index]),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
  });

  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = conversation.titleFor(currentUserId);
    final preview = conversation.lastMessage?.previewFor(currentUserId).trim();
    final unread = conversation.unreadCountFor(currentUserId);
    final hasUnread = unread > 0;
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: unread > 0 ? '$title, $unread tin nhắn chưa đọc' : title,
      child: Card(
        elevation: 0,
        color: hasUnread
            ? colors.primaryContainer.withValues(alpha: 0.38)
            : colors.surface,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ChatAvatar(
                      label: title,
                      imageUrl: conversation.avatarUrlFor(currentUserId),
                      isGroup: conversation.isGroup,
                    ),
                    if (conversation.isGroup)
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.surface, width: 2),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(
                              Icons.groups_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: hasUnread
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _conversationTime(conversation.lastMessageAt),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: hasUnread
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : null,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview == null || preview.isEmpty
                                  ? 'Bắt đầu cuộc trò chuyện'
                                  : preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: hasUnread
                                        ? colors.onSurface
                                        : colors.onSurfaceVariant,
                                    fontWeight: hasUnread
                                        ? FontWeight.w600
                                        : null,
                                  ),
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: 10),
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 22,
                                minHeight: 22,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [flowPurple, flowPink],
                                ),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
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

class _NewChatOption extends StatelessWidget {
  const _NewChatOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: FlowGradient(
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.all(11),
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

String _conversationTime(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final valueDay = DateTime(local.year, local.month, local.day);
  final difference = today.difference(valueDay).inDays;

  if (difference == 0) return DateFormat('HH:mm').format(local);
  if (difference == 1) return 'Hôm qua';
  if (local.year == now.year) return DateFormat('dd/MM').format(local);
  return DateFormat('dd/MM/yy').format(local);
}
