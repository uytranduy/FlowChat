import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../models/friend_request.dart';
import '../../state/app_controller.dart';
import '../../widgets/state_views.dart';
import '../../widgets/user_avatar.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<FriendRequest> _received = const [];
  List<FriendRequest> _sent = const [];
  bool _loading = true;
  String? _error;
  String? _workingId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context
          .read<AppController>()
          .friendService
          .getFriendRequests();
      if (!mounted) return;
      setState(() {
        _received = result.received;
        _sent = result.sent;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _requestError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(FriendRequest request) async {
    setState(() => _workingId = request.id);
    try {
      await context.read<AppController>().friendService.acceptFriendRequest(
        request.id,
      );
      if (!mounted) return;
      setState(
        () => _received = _received.where((r) => r.id != request.id).toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hai bạn đã trở thành bạn bè.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_requestError(error))));
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  Future<void> _decline(FriendRequest request) async {
    setState(() => _workingId = request.id);
    try {
      await context.read<AppController>().friendService.declineFriendRequest(
        request.id,
      );
      if (!mounted) return;
      setState(
        () => _received = _received.where((r) => r.id != request.id).toList(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_requestError(error))));
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lời mời kết bạn'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Đã nhận (${_received.length})'),
            Tab(text: 'Đã gửi (${_sent.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _RequestList(
                  requests: _received,
                  received: true,
                  workingId: _workingId,
                  onAccept: _accept,
                  onDecline: _decline,
                  onRefresh: _load,
                ),
                _RequestList(
                  requests: _sent,
                  received: false,
                  workingId: _workingId,
                  onAccept: _accept,
                  onDecline: _decline,
                  onRefresh: _load,
                ),
              ],
            ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({
    required this.requests,
    required this.received,
    required this.workingId,
    required this.onAccept,
    required this.onDecline,
    required this.onRefresh,
  });

  final List<FriendRequest> requests;
  final bool received;
  final String? workingId;
  final ValueChanged<FriendRequest> onAccept;
  final ValueChanged<FriendRequest> onDecline;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.58,
              child: EmptyStateView(
                icon: Icons.mark_email_read_outlined,
                title: received
                    ? 'Không có lời mời mới'
                    : 'Chưa gửi lời mời nào',
                message: received
                    ? 'Lời mời mới sẽ xuất hiện tại đây.'
                    : 'Bạn có thể tìm người dùng bằng username.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final request = requests[index];
          final person = received ? request.from : request.to;
          final busy = workingId == request.id;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        name: person?.displayName ?? 'Người dùng FlowChat',
                        avatarUrl: person?.avatarUrl,
                        radius: 23,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person?.displayName ?? 'Người dùng',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text('@${person?.username ?? ''}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (request.message.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lời giới thiệu',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(request.message.trim()),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (received)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy ? null : () => onDecline(request),
                            child: const Text('Từ chối'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: busy ? null : () => onAccept(request),
                            child: busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Chấp nhận'),
                          ),
                        ),
                      ],
                    )
                  else
                    const Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Đang chờ trả lời'),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _requestError(Object error) {
  if (error is ApiException) return error.message;
  return 'Không thể tải lời mời kết bạn.';
}
