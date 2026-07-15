import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/conversation_list_screen.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';
import '../../state/app_controller.dart';
import '../../state/call_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _unreadCount = 0;
  int _friendRequestCount = 0;
  int _handledFriendRequestRevision = 0;
  bool _initialized = false;
  bool _friendRequestsInitialized = false;
  Set<String> _knownFriendRequestIds = const {};
  CallController? _callController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final callController = context.read<CallController>();
    if (!identical(_callController, callController)) {
      _callController?.removeListener(_handleFriendRequestSignal);
      _callController = callController;
      _handledFriendRequestRevision = callController.friendRequestRevision;
      callController.addListener(_handleFriendRequestSignal);
    }
    if (_initialized) return;
    _initialized = true;
    unawaited(_refreshFriendRequests());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshFriendRequests());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callController?.removeListener(_handleFriendRequestSignal);
    super.dispose();
  }

  void _handleFriendRequestSignal() {
    final callController = _callController;
    if (!mounted || callController == null) return;
    final revision = callController.friendRequestRevision;
    if (revision <= _handledFriendRequestRevision) return;
    _handledFriendRequestRevision = revision;
    unawaited(
      _refreshFriendRequests(
        showNotification: callController.friendRequestReceived,
        senderName: callController.friendRequestSenderName,
      ),
    );
  }

  Future<void> _refreshFriendRequests({
    bool showNotification = false,
    String? senderName,
  }) async {
    try {
      final requests = await context
          .read<AppController>()
          .friendService
          .getFriendRequests();
      if (!mounted) return;
      final requestIds = requests.received.map((request) => request.id).toSet();
      final newRequests = requests.received
          .where((request) => !_knownFriendRequestIds.contains(request.id))
          .toList(growable: false);
      final discoveredWhileAway =
          _friendRequestsInitialized && newRequests.isNotEmpty;
      _knownFriendRequestIds = Set.unmodifiable(requestIds);
      _friendRequestsInitialized = true;
      setState(() => _friendRequestCount = requests.received.length);
      if (context.read<AppController>().currentUser?.notificationsEnabled ==
          false) {
        return;
      }
      if (!showNotification && !discoveredWhileAway) return;

      final discoveredSenderName = newRequests.isEmpty
          ? null
          : newRequests.first.from?.displayName;
      final displayName = (senderName ?? discoveredSenderName)?.trim();
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              displayName == null || displayName.isEmpty
                  ? 'Bạn có một lời mời kết bạn mới.'
                  : '$displayName đã gửi cho bạn một lời mời kết bạn.',
            ),
            action: SnackBarAction(
              label: 'Xem',
              onPressed: () {
                if (mounted) setState(() => _selectedIndex = 1);
              },
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      // A reconnect or app resume will retry without interrupting the user.
    }
  }

  void _handleUnreadCountChanged(int totalUnread, int newlyUnread) {
    if (!mounted) return;
    if (_unreadCount != totalUnread) {
      setState(() => _unreadCount = totalUnread);
    }
    if (newlyUnread <= 0 ||
        context.read<AppController>().currentUser?.notificationsEnabled ==
            false) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            newlyUnread == 1
                ? 'Bạn có một tin nhắn mới.'
                : 'Bạn có $newlyUnread tin nhắn mới.',
          ),
          action: _selectedIndex == 0
              ? null
              : SnackBarAction(
                  label: 'Xem',
                  onPressed: () {
                    if (mounted) setState(() => _selectedIndex = 0);
                  },
                ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ConversationListScreen(
            onUnreadCountChanged: _handleUnreadCountChanged,
          ),
          FriendsScreen(requestCount: _friendRequestCount),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text(_unreadCount > 99 ? '99+' : '$_unreadCount'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text(_unreadCount > 99 ? '99+' : '$_unreadCount'),
              child: const Icon(Icons.chat_bubble_rounded),
            ),
            label: 'Trò chuyện',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _friendRequestCount > 0,
              label: Text(
                _friendRequestCount > 99 ? '99+' : '$_friendRequestCount',
              ),
              child: const Icon(Icons.people_outline_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: _friendRequestCount > 0,
              label: Text(
                _friendRequestCount > 99 ? '99+' : '$_friendRequestCount',
              ),
              child: const Icon(Icons.people_rounded),
            ),
            label: 'Bạn bè',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }
}
