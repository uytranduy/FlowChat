import 'package:dio/dio.dart';
import 'package:flowchat_mobile/app.dart';
import 'package:flowchat_mobile/core/network/api_client.dart';
import 'package:flowchat_mobile/core/network/api_exception.dart';
import 'package:flowchat_mobile/core/config/app_config.dart';
import 'package:flowchat_mobile/core/utils/presence.dart';
import 'package:flowchat_mobile/models/conversation.dart';
import 'package:flowchat_mobile/models/message.dart';
import 'package:flowchat_mobile/models/user.dart';
import 'package:flowchat_mobile/models/voice_call.dart';
import 'package:flowchat_mobile/screens/chat/chat_widgets.dart';
import 'package:flowchat_mobile/screens/profile/profile_screen.dart';
import 'package:flowchat_mobile/state/app_controller.dart';
import 'package:flowchat_mobile/state/call_controller.dart';
import 'package:flowchat_mobile/theme/app_theme.dart';
import 'package:flowchat_mobile/widgets/flow_chat_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('REST model parsing', () {
    test('parses a complete user', () {
      final user = User.fromJson({
        '_id': 'user-1',
        'username': 'flow',
        'email': 'flow@example.com',
        'displayName': 'Flow User',
        'authProvider': 'google',
      });

      expect(user.id, 'user-1');
      expect(user.username, 'flow');
      expect(user.displayName, 'Flow User');
      expect(user.usesGoogleAuth, isTrue);
    });

    test('accepts populated and plain ObjectId conversation fields', () {
      final conversation = Conversation.fromJson({
        '_id': 'conversation-1',
        'type': 'direct',
        'participants': [
          {'_id': 'me', 'displayName': 'Tôi'},
          {
            '_id': 'friend',
            'displayName': 'Bạn',
            'username': 'nguoi_ban',
            'bio': 'Xin chào FlowChat',
          },
        ],
        'seenBy': ['me'],
        'unreadCounts': {'me': 2},
        'lastMessage': {
          '_id': 'message-1',
          'content': 'Xin chào',
          'senderId': {'_id': 'friend', 'displayName': 'Bạn'},
          'createdAt': '2026-07-13T12:00:00.000Z',
        },
      });

      expect(conversation.otherParticipant('me')?.id, 'friend');
      expect(conversation.otherParticipant('me')?.username, 'nguoi_ban');
      expect(conversation.otherParticipant('me')?.bio, 'Xin chào FlowChat');
      expect(conversation.titleFor('me'), 'Bạn');
      expect(conversation.unreadCountFor('me'), 2);
      expect(conversation.lastMessage?.senderId, 'friend');
    });

    test('message parser falls back safely for missing optional fields', () {
      final message = Message.fromJson({
        '_id': 'message-1',
        'conversationId': 'conversation-1',
        'senderId': 'user-1',
        'content': 'Nội dung',
        'createdAt': '2026-07-13T12:00:00.000Z',
      });

      expect(message.content, 'Nội dung');
      expect(message.isOwn('user-1'), isTrue);
      expect(message.imgUrl, isNull);
    });

    test('parses pinned message metadata', () {
      final message = Message.fromJson({
        '_id': 'message-pinned-1',
        'conversationId': 'conversation-1',
        'senderId': 'user-1',
        'content': 'Tin nhắn quan trọng',
        'pinnedAt': '2026-07-17T10:30:00.000Z',
        'pinnedBy': 'user-2',
        'createdAt': '2026-07-17T10:00:00.000Z',
      });

      expect(message.isPinned, isTrue);
      expect(message.pinnedBy, 'user-2');
      expect(message.pinnedAt, DateTime.utc(2026, 7, 17, 10, 30));

      final unpinned = Message.fromJson({
        '_id': 'message-pinned-1',
        'conversationId': 'conversation-1',
        'senderId': 'user-1',
        'content': 'Tin nhắn quan trọng',
        'pinnedAt': null,
        'pinnedBy': null,
        'createdAt': '2026-07-17T10:00:00.000Z',
      });
      expect(unpinned.isPinned, isFalse);
      expect(unpinned.pinnedBy, isEmpty);
    });

    test('parses group invitation permission and system messages', () {
      final conversation = Conversation.fromJson({
        '_id': 'group-1',
        'type': 'group',
        'group': {
          'name': 'Nhóm CDE',
          'createdBy': 'owner-1',
          'allowMembersToInvite': false,
          'allowMembersToRename': false,
          'dissolvedAt': '2026-07-15T12:00:00.000Z',
          'dissolvedBy': 'owner-1',
        },
        'participants': const [],
        'seenBy': const [],
        'unreadCounts': const {},
      });
      final message = Message.fromJson({
        '_id': 'system-1',
        'conversationId': 'group-1',
        'senderId': 'member-1',
        'content': 'Người dùng A đã vào nhóm CDE',
        'messageType': 'system',
        'createdAt': '2026-07-15T12:00:00.000Z',
      });

      expect(conversation.group?.allowMembersToInvite, isFalse);
      expect(conversation.group?.allowMembersToRename, isFalse);
      expect(conversation.group?.isDissolved, isTrue);
      expect(conversation.group?.dissolvedById, 'owner-1');
      expect(message.messageType, MessageType.system);
    });

    test('parses call history metadata from the backend contract', () {
      final message = Message.fromJson({
        '_id': 'message-call-1',
        'conversationId': 'conversation-1',
        'senderId': 'caller-1',
        'messageType': 'call',
        'content': 'Cuộc gọi video',
        'createdAt': '2026-07-13T12:00:00.000Z',
        'call': {
          'callId': 'call-1',
          'mediaType': 'video',
          'callerId': 'caller-1',
          'calleeId': 'callee-1',
          'reason': 'ended',
          'durationSeconds': 152,
          'startedAt': '2026-07-13T12:00:00.000Z',
          'acceptedAt': '2026-07-13T12:00:03.000Z',
          'endedAt': '2026-07-13T12:02:35.000Z',
        },
      });

      expect(message.isCall, isTrue);
      expect(message.call?.mediaType, CallMediaType.video);
      expect(message.call?.isOutgoingFor('caller-1'), isTrue);
      expect(message.call?.durationSeconds, 152);
      expect(formatCallDuration(152), '2 phút 32 giây');
      expect(formatCallDuration(0), '0 phút 0 giây');
    });

    test('shows the called user name when their account is logged out', () {
      expect(
        loggedOutCallMessage('Nguyễn Bình'),
        'Người dùng Nguyễn Bình hiện đã đăng xuất khỏi tài khoản nên không thể nhận cuộc gọi.',
      );
      expect(
        loggedOutCallMessage(''),
        'Người dùng này hiện đã đăng xuất khỏi tài khoản nên không thể nhận cuộc gọi.',
      );
    });

    test('parses group call history metadata from the backend contract', () {
      final message = Message.fromJson({
        '_id': 'message-group-call-1',
        'conversationId': 'conversation-group-1',
        'senderId': 'caller-1',
        'messageType': 'call',
        'content': 'Cuộc gọi video nhóm',
        'createdAt': '2026-07-15T12:00:00.000Z',
        'call': {
          'callId': 'group-call-1',
          'callType': 'group',
          'mediaType': 'video',
          'callerId': 'caller-1',
          'participantCount': 4,
          'reason': 'ended',
          'durationSeconds': 315,
          'startedAt': '2026-07-15T12:00:00.000Z',
          'endedAt': '2026-07-15T12:05:15.000Z',
        },
      });

      expect(message.call?.isGroup, isTrue);
      expect(message.call?.participantCount, 4);
      expect(message.call?.calleeId, isEmpty);
      expect(message.call?.durationSeconds, 315);
    });

    test('parses call metadata in conversation last-message previews', () {
      final conversation = Conversation.fromJson({
        '_id': 'conversation-call-1',
        'type': 'direct',
        'participants': [
          {'_id': 'caller-1', 'displayName': 'Người gọi'},
          {'_id': 'callee-1', 'displayName': 'Người nhận'},
        ],
        'seenBy': const [],
        'unreadCounts': const {},
        'lastMessage': {
          '_id': 'message-call-1',
          'content': 'Cuộc gọi video',
          'senderId': 'caller-1',
          'messageType': 'call',
          'createdAt': '2026-07-13T12:02:35.000Z',
          'call': {
            'callId': 'call-1',
            'mediaType': 'video',
            'callerId': 'caller-1',
            'calleeId': 'callee-1',
            'reason': 'ended',
            'durationSeconds': 152,
            'startedAt': '2026-07-13T12:00:00.000Z',
            'acceptedAt': '2026-07-13T12:00:03.000Z',
            'endedAt': '2026-07-13T12:02:35.000Z',
          },
        },
      });

      expect(conversation.lastMessage?.messageType, MessageType.call);
      expect(
        conversation.lastMessage?.previewFor('caller-1'),
        'Cuộc gọi video đi · 2 phút 32 giây',
      );
      expect(
        conversation.lastMessage?.previewFor('callee-1'),
        'Cuộc gọi video đến · 2 phút 32 giây',
      );
    });

    test('builds attachment previews from last-message summaries', () {
      final conversation = Conversation.fromJson({
        '_id': 'conversation-file-1',
        'type': 'direct',
        'participants': const [],
        'seenBy': const [],
        'unreadCounts': const {},
        'lastMessage': {
          '_id': 'message-file-1',
          'content': '',
          'senderId': 'sender-1',
          'messageType': 'attachment',
          'attachment': {'kind': 'file', 'fileName': 'tailieu.pdf'},
          'createdAt': '2026-07-13T12:02:35.000Z',
        },
      });

      expect(
        conversation.lastMessage?.previewFor('sender-1'),
        '📎 tailieu.pdf',
      );
    });

    test('parses reply, recall, reactions, and forwarding metadata', () {
      final message = Message.fromJson({
        '_id': 'message-2',
        'conversationId': 'conversation-1',
        'senderId': 'user-2',
        'content': 'Tin nhắn chuyển tiếp',
        'messageType': 'text',
        'isRecalled': false,
        'recalledAt': null,
        'replyTo': {
          'messageId': 'message-1',
          'senderId': 'user-1',
          'content': 'Tin nhắn gốc',
          'messageType': 'text',
          'isRecalled': true,
        },
        'reactions': [
          {
            'userId': 'user-1',
            'emoji': '👍',
            'createdAt': '2026-07-13T12:01:00.000Z',
          },
          {
            'userId': 'user-2',
            'emoji': '👍',
            'createdAt': '2026-07-13T12:01:01.000Z',
          },
          {
            'userId': 'user-3',
            'emoji': '❤️',
            'createdAt': '2026-07-13T12:01:02.000Z',
          },
        ],
        'forwardedFrom': {'messageId': 'message-original'},
        'createdAt': '2026-07-13T12:02:00.000Z',
      });

      expect(message.replyTo?.messageId, 'message-1');
      expect(message.replyTo?.isRecalled, isTrue);
      expect(message.reactions, hasLength(3));
      expect(message.hasReaction('user-1', '👍'), isTrue);
      expect(message.isForwarded, isTrue);
      expect(message.forwardedFrom?.messageId, 'message-original');
    });

    test('parses image, video and file attachment metadata', () {
      final message = Message.fromJson({
        '_id': 'message-attachment-1',
        'conversationId': 'conversation-1',
        'senderId': 'user-2',
        'content': 'Tài liệu của nhóm',
        'messageType': 'attachment',
        'attachment': {
          'kind': 'file',
          'url': 'https://cdn.example.com/tailieu.pdf',
          'publicId': 'flowchat/tailieu',
          'fileName': 'tailieu.pdf',
          'mimeType': 'application/pdf',
          'sizeBytes': 1048576,
        },
        'replyTo': {
          'messageId': 'message-image-1',
          'senderId': 'user-1',
          'messageType': 'attachment',
          'isRecalled': false,
          'attachment': {'kind': 'image', 'fileName': 'anh.png'},
        },
        'createdAt': '2026-07-13T12:02:00.000Z',
      });

      expect(message.messageType, MessageType.attachment);
      expect(message.isAttachment, isTrue);
      expect(message.attachment?.kind, MessageAttachmentKind.file);
      expect(message.attachment?.fileName, 'tailieu.pdf');
      expect(message.attachment?.sizeBytes, 1048576);
      expect(message.replyTo?.attachment?.kind, MessageAttachmentKind.image);
      expect(replyAttachmentLabel(message.replyTo!.attachment!), 'Hình ảnh');
      expect(formatFileSize(message.attachment!.sizeBytes), '1.0 MB');
    });
  });

  group('REST infrastructure', () {
    test('extracts refreshToken from Set-Cookie', () {
      final client = ApiClient();
      final headers = Headers.fromMap({
        'set-cookie': [
          'refreshToken=abc123; Max-Age=1209600; Path=/; HttpOnly; Secure',
        ],
      });

      expect(client.refreshTokenFromHeaders(headers), 'abc123');
    });

    test('reads string and object API errors', () {
      expect(
        ApiException.messageFromData({
          'message': 'Không hợp lệ',
        }, fallback: 'fallback'),
        'Không hợp lệ',
      );
      expect(
        ApiException.messageFromData('Thiếu nội dung', fallback: 'fallback'),
        'Thiếu nội dung',
      );
    });
  });

  group('Voice call configuration', () {
    test('derives the Socket.IO host from the REST API URL', () {
      expect(AppConfig.socketBaseUrl, 'http://10.0.2.2:5001');
    });

    test('parses a cross-platform caller payload', () {
      final peer = CallPeer.fromJson({
        'id': 'caller-1',
        'displayName': 'Người gọi',
        'avatarUrl': 'https://example.com/avatar.png',
      });

      expect(peer.id, 'caller-1');
      expect(peer.displayName, 'Người gọi');
      expect(peer.avatarUrl, 'https://example.com/avatar.png');
    });

    test('preserves the final SDP line terminator required by libwebrtc', () {
      const sdp = 'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\n';

      expect(CallController.normalizeSessionDescriptionSdp(sdp), sdp);
      expect(
        CallController.normalizeSessionDescriptionSdp('v=0\r\ns=-'),
        'v=0\r\ns=-\r\n',
      );
      expect(CallController.normalizeSessionDescriptionSdp('   '), isNull);
    });
  });

  group('Chat presentation', () {
    test('formats online and last active presence', () {
      final now = DateTime.utc(2026, 7, 15, 12);
      expect(presenceText(isOnline: true, now: now), 'Đang hoạt động');
      expect(
        presenceText(
          isOnline: false,
          lastSeenAt: now.subtract(const Duration(minutes: 12)),
          now: now,
        ),
        'Hoạt động 12 phút trước',
      );
      expect(
        presenceText(isOnline: false, presenceVisible: false, now: now),
        'Không hiển thị trạng thái hoạt động',
      );
    });

    test('shows a centered time marker only after a gap over five minutes', () {
      final first = DateTime.utc(2026, 7, 13, 12);

      expect(shouldShowMessageTime(null, first), isTrue);
      expect(
        shouldShowMessageTime(first, first.add(const Duration(minutes: 5))),
        isFalse,
      );
      expect(
        shouldShowMessageTime(
          first,
          first.add(const Duration(minutes: 5, seconds: 1)),
        ),
        isTrue,
      );
    });

    test('groups reactions and marks the current user reaction', () {
      final summaries = summarizeMessageReactions(const [
        MessageReaction(userId: 'me', emoji: '👍'),
        MessageReaction(userId: 'friend', emoji: '👍'),
        MessageReaction(userId: 'friend', emoji: '❤️'),
      ], 'me');

      expect(summaries, hasLength(2));
      expect(summaries.first.emoji, '👍');
      expect(summaries.first.count, 2);
      expect(summaries.first.reactedByCurrentUser, isTrue);
      expect(summaries.last.emoji, '❤️');
      expect(summaries.last.reactedByCurrentUser, isFalse);
    });

    test('detects same-id message presentation updates for polling', () {
      final createdAt = DateTime.utc(2026, 7, 13, 12);
      final before = Message(
        id: 'message-1',
        conversationId: 'conversation-1',
        senderId: 'friend',
        content: 'Xin chào',
        createdAt: createdAt,
      );
      final reacted = Message(
        id: 'message-1',
        conversationId: 'conversation-1',
        senderId: 'friend',
        content: 'Xin chào',
        createdAt: createdAt,
        updatedAt: createdAt.add(const Duration(seconds: 1)),
        reactions: const [MessageReaction(userId: 'me', emoji: '👍')],
      );

      expect(hasMessagePresentationChanged(before, before), isFalse);
      expect(hasMessagePresentationChanged(before, reacted), isTrue);
    });

    test('counts new unread per conversation instead of only total delta', () {
      expect(countNewUnread(null, const {'a': 2}), 0);
      expect(countNewUnread(const {'a': 3, 'b': 0}, const {'a': 0, 'b': 2}), 2);
      expect(
        countNewUnread(const {'a': 1}, const {'a': 1, 'new-conversation': 3}),
        3,
      );
    });
  });

  testWidgets('renders the FlowChat brand in both themes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Center(child: FlowChatLogo())),
      ),
    );

    expect(find.text('FlowChat'), findsOneWidget);
    expect(find.byIcon(Icons.forum_rounded), findsOneWidget);
  });

  testWidgets('builds the application shell with a valid Router context', (
    tester,
  ) async {
    final controller = AppController();
    await tester.pumpWidget(FlowChatApp(controller: controller));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('FlowChat'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('profile dialogs keep controllers alive during close animation', (
    tester,
  ) async {
    final controller = AppController()
      ..currentUser = const User(
        id: 'me',
        username: 'flow_user',
        email: 'flow@example.com',
        displayName: 'Flow User',
      );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );

    await tester.ensureVisible(find.text('Chỉnh sửa hồ sơ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chỉnh sửa hồ sơ'));
    await tester.pumpAndSettle();
    expect(find.text('Chỉnh sửa thông tin'), findsOneWidget);
    await tester.tap(find.text('Huỷ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Đổi mật khẩu'));
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đổi mật khẩu').first);
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu hiện tại'), findsOneWidget);
    await tester.tap(find.text('Huỷ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
