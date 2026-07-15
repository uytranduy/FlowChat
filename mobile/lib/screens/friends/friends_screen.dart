import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../models/user.dart';
import '../../state/app_controller.dart';
import '../../widgets/flow_chat_logo.dart';
import '../../widgets/state_views.dart';
import '../../widgets/user_avatar.dart';
import '../chat/chat_screen.dart';
import 'add_friend_screen.dart';
import 'friend_requests_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.requestCount = 0});

  final int requestCount;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchController = TextEditingController();
  List<User> _friends = const [];
  bool _loading = true;
  String? _error;
  String? _openingFriendId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final service = context.read<AppController>().friendService;
      final friends = await service.getFriends();
      if (!mounted) return;
      setState(() {
        _friends = friends;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRequests() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FriendRequestsScreen()));
    if (mounted) await _load();
  }

  Future<void> _openAddFriend() async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddFriendScreen()));
    if (changed == true && mounted) await _load();
  }

  Future<void> _startConversation(User friend) async {
    if (_openingFriendId != null) return;
    setState(() => _openingFriendId = friend.id);
    try {
      final conversation = await context
          .read<AppController>()
          .chatService
          .createDirectConversation(friend.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversation: conversation,
            onConversationChanged: _load,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
    } finally {
      if (mounted) setState(() => _openingFriendId = null);
    }
  }

  List<User> get _filteredFriends {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _friends;
    return _friends
        .where(
          (friend) =>
              friend.displayName.toLowerCase().contains(query) ||
              friend.username.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredFriends;
    return Scaffold(
      appBar: AppBar(
        title: const FlowChatLogo(size: 34),
        actions: [
          Badge(
            isLabelVisible: widget.requestCount > 0,
            label: Text(
              widget.requestCount > 99 ? '99+' : '${widget.requestCount}',
            ),
            child: IconButton(
              tooltip: 'Lời mời kết bạn',
              onPressed: _openRequests,
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-friend',
        onPressed: _openAddFriend,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Thêm bạn'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Tìm trong danh sách bạn bè',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 48),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyStateView(
                  icon: _friends.isEmpty
                      ? Icons.people_outline_rounded
                      : Icons.search_off_rounded,
                  title: _friends.isEmpty
                      ? 'Chưa có bạn bè'
                      : 'Không tìm thấy người phù hợp',
                  message: _friends.isEmpty
                      ? 'Tìm username để gửi lời mời kết bạn.'
                      : 'Hãy thử một tên hoặc username khác.',
                  action: _friends.isEmpty
                      ? FilledButton.icon(
                          onPressed: _openAddFriend,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Thêm bạn'),
                        )
                      : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final friend = filtered[index];
                    final opening = _openingFriendId == friend.id;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: UserAvatar(
                          name: friend.displayName,
                          avatarUrl: friend.avatarUrl,
                          radius: 24,
                        ),
                        title: Text(friend.displayName),
                        subtitle: Text('@${friend.username}'),
                        trailing: opening
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chat_bubble_outline_rounded),
                        onTap: opening
                            ? null
                            : () => _startConversation(friend),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _messageFor(Object error) {
  if (error is ApiException) return error.message;
  return 'Không thể kết nối tới máy chủ. Vui lòng thử lại.';
}
