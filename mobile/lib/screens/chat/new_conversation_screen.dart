import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../models/user.dart';
import '../../state/app_controller.dart';
import 'chat_widgets.dart';

enum NewConversationMode { direct, group }

class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key, required this.mode});

  final NewConversationMode mode;

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final _searchController = TextEditingController();
  final _groupNameController = TextEditingController();
  final Set<String> _selectedIds = {};

  List<User> _friends = const [];
  Map<String, Conversation> _directByFriendId = const {};
  bool _initialized = false;
  bool _loading = true;
  bool _creating = false;
  String? _error;

  bool get _isGroup => widget.mode == NewConversationMode.group;
  AppController get _app => context.read<AppController>();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_update);
    _groupNameController.addListener(_update);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _loadFriends();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_update)
      ..dispose();
    _groupNameController
      ..removeListener(_update)
      ..dispose();
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFriends() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      List<Conversation> conversations = const [];
      try {
        conversations = await _app.chatService.getConversations();
      } catch (_) {
        // The friend picker remains usable if conversation previews cannot be
        // refreshed; opening a friend still asks the server for the direct chat.
      }
      final friends = await _app.friendService.getFriends();
      final byId = <String, User>{
        for (final friend in friends) friend.id: friend,
      };
      final currentUserId = _app.currentUser?.id ?? '';
      final directByFriendId = <String, Conversation>{};
      for (final conversation in conversations) {
        if (!conversation.isDirect) continue;
        final other = conversation.otherParticipant(currentUserId);
        if (other == null) continue;
        final previous = directByFriendId[other.id];
        final currentDate =
            conversation.lastMessage?.createdAt ??
            conversation.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final previousDate =
            previous?.lastMessage?.createdAt ??
            previous?.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final currentHasMessages = conversation.lastMessage != null;
        final previousHasMessages = previous?.lastMessage != null;
        if (previous == null ||
            (currentHasMessages && !previousHasMessages) ||
            (currentHasMessages == previousHasMessages &&
                currentDate.isAfter(previousDate))) {
          directByFriendId[other.id] = conversation;
        }
      }
      final sorted = byId.values.toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      if (!mounted) return;
      setState(() {
        _friends = sorted;
        _directByFriendId = Map.unmodifiable(directByFriendId);
        _selectedIds.removeWhere((id) => !byId.containsKey(id));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(
          error,
          fallback: 'Không thể tải danh sách bạn bè.',
        );
      });
    }
  }

  List<User> get _filteredFriends {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _friends;
    return _friends.where((friend) {
      return friend.displayName.toLowerCase().contains(query) ||
          friend.username.toLowerCase().contains(query);
    }).toList();
  }

  bool get _canCreate {
    if (_creating) return false;
    if (_isGroup) {
      return _selectedIds.isNotEmpty &&
          _groupNameController.text.trim().isNotEmpty;
    }
    return _selectedIds.length == 1;
  }

  void _toggleFriend(User friend) {
    setState(() {
      if (_isGroup) {
        if (!_selectedIds.add(friend.id)) _selectedIds.remove(friend.id);
      } else {
        if (_selectedIds.contains(friend.id)) {
          _selectedIds.clear();
        } else {
          _selectedIds
            ..clear()
            ..add(friend.id);
        }
      }
    });
  }

  Future<void> _createConversation() async {
    if (!_canCreate) return;
    setState(() => _creating = true);

    try {
      final selectedIds = _selectedIds.toList();
      final existing = !_isGroup && selectedIds.isNotEmpty
          ? _directByFriendId[selectedIds.first]
          : null;
      final conversation =
          existing ??
          await _app.chatService.createConversation(
            _isGroup ? 'group' : 'direct',
            name: _isGroup ? _groupNameController.text.trim() : null,
            memberIds: selectedIds,
          );
      if (!mounted) return;
      Navigator.of(context).pop<Conversation>(conversation);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Không thể tạo cuộc trò chuyện.'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = _filteredFriends;

    return Scaffold(
      appBar: AppBar(title: Text(_isGroup ? 'Tạo nhóm mới' : 'Tin nhắn mới')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_isGroup)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _groupNameController,
                  enabled: !_creating,
                  autofocus: true,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Tên nhóm',
                    hintText: 'Ví dụ: Nhóm dự án',
                    prefixIcon: const Icon(Icons.groups_rounded),
                    filled: true,
                    fillColor: colors.surfaceContainerHighest.withValues(
                      alpha: 0.52,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, _isGroup ? 4 : 12, 16, 8),
              child: TextField(
                controller: _searchController,
                enabled: !_creating,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm bạn bè',
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
                    alpha: 0.52,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_isGroup && _selectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Đã chọn ${_selectedIds.length} thành viên',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Expanded(child: _buildFriendList(filtered)),
            Material(
              elevation: 10,
              shadowColor: Colors.black26,
              color: colors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _canCreate ? _createConversation : null,
                    icon: _creating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.3,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isGroup
                                ? Icons.group_add_rounded
                                : Icons.chat_rounded,
                          ),
                    label: Text(
                      _creating
                          ? 'Đang tạo…'
                          : _isGroup
                          ? 'Tạo nhóm'
                          : 'Bắt đầu trò chuyện',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendList(List<User> friends) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null && _friends.isEmpty) {
      return ChatErrorView(message: _error!, onRetry: _loadFriends);
    }

    if (friends.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return RefreshIndicator(
        onRefresh: _loadFriends,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 70),
            Icon(
              searching
                  ? Icons.search_off_rounded
                  : Icons.people_outline_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              searching
                  ? 'Không tìm thấy người bạn phù hợp.'
                  : 'Bạn chưa có người bạn nào để trò chuyện.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFriends,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
        itemCount: friends.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final friend = friends[index];
          final selected = _selectedIds.contains(friend.id);
          final conversation = _directByFriendId[friend.id];
          final lastMessage = conversation?.lastMessage;
          final conversationPreview = lastMessage == null
              ? 'Chưa có tin nhắn nào trong cuộc trò chuyện này'
              : lastMessage.previewFor(_app.currentUser?.id ?? '');
          return Semantics(
            selected: selected,
            button: true,
            label: '${selected ? 'Bỏ chọn' : 'Chọn'} ${friend.displayName}',
            child: ListTile(
              enabled: !_creating,
              selected: selected,
              onTap: () => _toggleFriend(friend),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: ChatAvatar(
                label: friend.displayName,
                imageUrl: friend.avatarUrl,
                radius: 23,
              ),
              title: Text(
                friend.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (friend.username.isNotEmpty)
                    Text(
                      '@${friend.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (!_isGroup)
                    Text(
                      conversationPreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              trailing: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : _isGroup
                      ? Icons.circle_outlined
                      : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(selected),
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
