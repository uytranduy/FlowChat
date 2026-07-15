import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../widgets/user_avatar.dart';

const flowPurple = Color(0xFF7C3AED);
const flowPink = Color(0xFFEC4899);

class FlowGradient extends StatelessWidget {
  const FlowGradient({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [flowPurple, flowPink],
        ),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
  }
}

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.label,
    this.imageUrl,
    this.radius = 24,
    this.isGroup = false,
  });

  final String label;
  final String? imageUrl;
  final double radius;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: isGroup ? 'Ảnh nhóm $label' : 'Ảnh đại diện của $label',
      child: ExcludeSemantics(
        child: UserAvatar(
          name: label,
          avatarUrl: imageUrl,
          radius: radius,
          showStatus: false,
          isOnline: false,
        ),
      ),
    );
  }
}

class ChatErrorView extends StatelessWidget {
  const ChatErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 54, color: colors.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

String friendlyError(Object error, {String fallback = 'Đã có lỗi xảy ra.'}) {
  final raw = error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^Bad state:\s*'), '')
      .trim();
  if (raw.isEmpty || raw == 'null') return fallback;
  return raw;
}

bool shouldShowMessageTime(
  DateTime? previousMessageAt,
  DateTime currentMessageAt, {
  Duration gap = const Duration(minutes: 5),
}) {
  if (previousMessageAt == null) return true;
  return currentMessageAt.difference(previousMessageAt) > gap;
}

class MessageReactionSummary {
  const MessageReactionSummary({
    required this.emoji,
    required this.count,
    required this.reactedByCurrentUser,
    required this.userIds,
  });

  final String emoji;
  final int count;
  final bool reactedByCurrentUser;
  final List<String> userIds;
}

List<MessageReactionSummary> summarizeMessageReactions(
  Iterable<MessageReaction> reactions,
  String currentUserId,
) {
  final grouped = <String, List<MessageReaction>>{};
  for (final reaction in reactions) {
    grouped.putIfAbsent(reaction.emoji, () => []).add(reaction);
  }
  return grouped.entries
      .map(
        (entry) => MessageReactionSummary(
          emoji: entry.key,
          count: entry.value.length,
          reactedByCurrentUser: entry.value.any(
            (reaction) => reaction.userId == currentUserId,
          ),
          userIds: entry.value
              .map((reaction) => reaction.userId)
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
}

bool hasMessagePresentationChanged(Message previous, Message current) {
  if (previous.updatedAt != current.updatedAt ||
      previous.content != current.content ||
      previous.imgUrl != current.imgUrl ||
      previous.attachment?.url != current.attachment?.url ||
      previous.attachment?.kind != current.attachment?.kind ||
      previous.attachment?.fileName != current.attachment?.fileName ||
      previous.attachment?.mimeType != current.attachment?.mimeType ||
      previous.attachment?.sizeBytes != current.attachment?.sizeBytes ||
      previous.isRecalled != current.isRecalled ||
      previous.recalledAt != current.recalledAt ||
      previous.messageType != current.messageType ||
      previous.forwardedFrom?.messageId != current.forwardedFrom?.messageId ||
      previous.replyTo?.messageId != current.replyTo?.messageId ||
      previous.replyTo?.senderId != current.replyTo?.senderId ||
      previous.replyTo?.content != current.replyTo?.content ||
      previous.replyTo?.messageType != current.replyTo?.messageType ||
      previous.replyTo?.isRecalled != current.replyTo?.isRecalled ||
      previous.replyTo?.attachment?.kind != current.replyTo?.attachment?.kind ||
      previous.replyTo?.attachment?.fileName !=
          current.replyTo?.attachment?.fileName ||
      previous.reactions.length != current.reactions.length) {
    return true;
  }

  for (var index = 0; index < previous.reactions.length; index++) {
    final left = previous.reactions[index];
    final right = current.reactions[index];
    if (left.userId != right.userId ||
        left.emoji != right.emoji ||
        left.createdAt != right.createdAt) {
      return true;
    }
  }
  return false;
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return 'Không rõ dung lượng';
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String replyAttachmentLabel(ReplyAttachmentMetadata attachment) {
  return switch (attachment.kind) {
    MessageAttachmentKind.image => 'Hình ảnh',
    MessageAttachmentKind.video => 'Video',
    MessageAttachmentKind.file => attachment.fileName,
  };
}

int countNewUnread(Map<String, int>? previous, Map<String, int> current) {
  if (previous == null) return 0;
  return current.entries.fold<int>(0, (total, entry) {
    final increase = entry.value - (previous[entry.key] ?? 0);
    return total + (increase > 0 ? increase : 0);
  });
}
