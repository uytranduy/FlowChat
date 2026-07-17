import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../models/voice_call.dart';
import '../state/app_controller.dart';
import '../state/call_controller.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';
import 'group_call_overlay.dart' show InCallChatPanel;

class CallOverlay extends StatefulWidget {
  const CallOverlay({super.key});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  bool _chatOpen = false;

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallController>();
    if (call.status == VoiceCallStatus.idle) {
      if (_chatOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _chatOpen = false);
        });
      }
      return const SizedBox.shrink();
    }

    final canChat =
        call.status == VoiceCallStatus.active &&
        call.conversationId?.isNotEmpty == true &&
        call.peer != null;

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          call.mediaType.isVideo
              ? _VideoCallSurface(
                  call: call,
                  chatOpen: _chatOpen,
                  onChatToggle: () => setState(() => _chatOpen = !_chatOpen),
                )
              : _AudioCallSurface(
                  call: call,
                  chatOpen: _chatOpen,
                  onChatToggle: () => setState(() => _chatOpen = !_chatOpen),
                ),
          if (_chatOpen && canChat)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 64, 12, 104),
                child: InCallChatPanel(
                  conversationId: call.conversationId!,
                  chatService: context.read<AppController>().chatService,
                  currentUserId:
                      context.read<AppController>().currentUser?.id ?? '',
                  isGroup: false,
                  recipientId: call.peer!.id,
                  onClose: () => setState(() => _chatOpen = false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AudioCallSurface extends StatelessWidget {
  const _AudioCallSurface({
    required this.call,
    required this.chatOpen,
    required this.onChatToggle,
  });

  final CallController call;
  final bool chatOpen;
  final VoidCallback onChatToggle;

  @override
  Widget build(BuildContext context) {
    final peer = call.peer;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: 0.98),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primaryContainer,
              colors.surface,
              colors.secondaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Cuộc gọi FlowChat',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: FlowChatColors.brandGradient,
                  ),
                  child: UserAvatar(
                    name: peer?.displayName ?? 'FlowChat',
                    avatarUrl: peer?.avatarUrl,
                    radius: 58,
                    borderColor: colors.surface,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  peer?.displayName ?? 'Người dùng FlowChat',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                _CallStatus(call: call),
                const Spacer(),
                _CallActions(
                  call: call,
                  chatOpen: chatOpen,
                  onChatToggle: onChatToggle,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoCallSurface extends StatefulWidget {
  const _VideoCallSurface({
    required this.call,
    required this.chatOpen,
    required this.onChatToggle,
  });

  final CallController call;
  final bool chatOpen;
  final VoidCallback onChatToggle;

  @override
  State<_VideoCallSurface> createState() => _VideoCallSurfaceState();
}

class _VideoCallSurfaceState extends State<_VideoCallSurface> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  late final Future<void> _rendererInitialization;
  bool _renderersReady = false;
  bool _renderersDisposed = false;
  MediaStream? _attachedLocalStream;
  MediaStream? _attachedRemoteStream;

  @override
  void initState() {
    super.initState();
    _rendererInitialization = _initializeRendererInstances();
    unawaited(_completeRendererInitialization());
  }

  Future<void> _initializeRendererInstances() async {
    await _localRenderer.initialize();
    try {
      await _remoteRenderer.initialize();
    } catch (_) {
      await _localRenderer.dispose();
      rethrow;
    }
  }

  Future<void> _completeRendererInitialization() async {
    try {
      await _rendererInitialization;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _renderersReady = true;
    _syncStreams();
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _VideoCallSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncStreams();
  }

  void _syncStreams() {
    if (!_renderersReady) return;
    final local = widget.call.localStream;
    final remote = widget.call.remoteStream;
    if (!identical(local, _attachedLocalStream)) {
      _attachedLocalStream = local;
      _localRenderer.srcObject = local;
    }
    if (!identical(remote, _attachedRemoteStream)) {
      _attachedRemoteStream = remote;
      _remoteRenderer.srcObject = remote;
    }
  }

  Future<void> _disposeRenderersWhenReady() async {
    if (_renderersDisposed) return;
    _renderersDisposed = true;
    try {
      await _rendererInitialization;
    } catch (_) {
      return;
    }
    if (_renderersReady) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    }
    await Future.wait([_localRenderer.dispose(), _remoteRenderer.dispose()]);
  }

  @override
  void dispose() {
    unawaited(_disposeRenderersWhenReady());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final peer = call.peer;
    final hasRemoteVideo =
        _renderersReady &&
        call.remoteStream?.getVideoTracks().isNotEmpty == true;
    final hasLocalVideo =
        _renderersReady &&
        call.localStream?.getVideoTracks().isNotEmpty == true;

    return Material(
      color: const Color(0xFF090A11),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasRemoteVideo)
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _VideoWaitingBackground(call: call),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.62),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.78),
                ],
                stops: const [0, 0.44, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
              child: Column(
                children: [
                  Text(
                    peer?.displayName ?? 'Người dùng FlowChat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _CallStatus(call: call, foregroundColor: Colors.white70),
                  const Spacer(),
                  if (hasLocalVideo)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 112,
                        height: 158,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFF202231),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white24),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 18,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RTCVideoView(
                              _localRenderer,
                              mirror: call.isFrontCamera,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                            if (!call.cameraEnabled)
                              const ColoredBox(
                                color: Color(0xFF202231),
                                child: Center(
                                  child: Icon(
                                    Icons.videocam_off_rounded,
                                    color: Colors.white70,
                                    size: 34,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  _CallActions(
                    call: call,
                    chatOpen: widget.chatOpen,
                    onChatToggle: widget.onChatToggle,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoWaitingBackground extends StatelessWidget {
  const _VideoWaitingBackground({required this.call});

  final CallController call;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF27143E), Color(0xFF10131E), Color(0xFF3A1734)],
        ),
      ),
      child: Center(
        child: UserAvatar(
          name: call.peer?.displayName ?? 'FlowChat',
          avatarUrl: call.peer?.avatarUrl,
          radius: 66,
          borderColor: Colors.white24,
        ),
      ),
    );
  }
}

class _CallStatus extends StatelessWidget {
  const _CallStatus({required this.call, this.foregroundColor});

  final CallController call;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        _statusText(call),
        key: ValueKey(
          '${call.status}-${call.elapsed.inSeconds}-${call.endedDurationSeconds}',
        ),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: call.errorMessage == null
              ? foregroundColor ?? colors.onSurfaceVariant
              : colors.error,
        ),
      ),
    );
  }
}

String _statusText(CallController call) {
  if (call.errorMessage case final message?) return message;
  switch (call.status) {
    case VoiceCallStatus.idle:
      return '';
    case VoiceCallStatus.outgoing:
      return 'Đang đổ chuông…';
    case VoiceCallStatus.incoming:
      if (call.operationPending) {
        return call.mediaType.isVideo
            ? 'Đang mở camera và micrô…'
            : 'Đang mở micrô…';
      }
      return call.mediaType.isVideo
          ? 'Cuộc gọi video đến'
          : 'Cuộc gọi thoại đến';
    case VoiceCallStatus.connecting:
      return call.mediaType.isVideo
          ? 'Đang kết nối video…'
          : 'Đang kết nối âm thanh…';
    case VoiceCallStatus.active:
      final minutes = call.elapsed.inMinutes.toString().padLeft(2, '0');
      final seconds = (call.elapsed.inSeconds % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    case VoiceCallStatus.ended:
      final ended = _endedText(
        call.endedReason,
        call.mediaType,
        call.peer?.displayName,
      );
      if (call.endedDurationSeconds <= 0) return ended;
      return '$ended • ${formatCallDuration(call.endedDurationSeconds)}';
  }
}

String _endedText(
  String? reason,
  CallMediaType mediaType,
  String? peerDisplayName,
) {
  return switch (reason) {
    'declined' => 'Người nhận đã từ chối cuộc gọi',
    'busy' => 'Người nhận đang bận',
    'no-answer' => 'Không có người trả lời',
    'unavailable' => loggedOutCallMessage(peerDisplayName),
    'canceled' => 'Cuộc gọi đã bị hủy',
    'disconnected' => 'Cuộc gọi bị ngắt kết nối',
    'connection-failed' =>
      mediaType.isVideo
          ? 'Không thể kết nối video'
          : 'Không thể kết nối âm thanh',
    'answered-elsewhere' => 'Cuộc gọi đã được nhận trên thiết bị khác',
    'media-error' =>
      mediaType.isVideo
          ? 'Không thể sử dụng camera hoặc micrô'
          : 'Không thể sử dụng micrô',
    _ => 'Cuộc gọi đã kết thúc',
  };
}

class _CallActions extends StatelessWidget {
  const _CallActions({
    required this.call,
    required this.chatOpen,
    required this.onChatToggle,
  });

  final CallController call;
  final bool chatOpen;
  final VoidCallback onChatToggle;

  @override
  Widget build(BuildContext context) {
    final isVideo = call.mediaType.isVideo;
    final colors = Theme.of(context).colorScheme;
    switch (call.status) {
      case VoiceCallStatus.incoming:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundCallButton(
              icon: Icons.call_end_rounded,
              label: 'Từ chối',
              color: Theme.of(context).colorScheme.error,
              onPressed: call.operationPending ? null : call.reject,
              darkSurface: isVideo,
            ),
            _RoundCallButton(
              icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              label: 'Nghe máy',
              color: FlowChatColors.online,
              onPressed: call.operationPending ? null : call.accept,
              darkSurface: isVideo,
            ),
          ],
        );
      case VoiceCallStatus.outgoing:
        return _RoundCallButton(
          icon: Icons.call_end_rounded,
          label: 'Hủy',
          color: Theme.of(context).colorScheme.error,
          onPressed: call.hangUp,
          darkSurface: isVideo,
        );
      case VoiceCallStatus.connecting:
      case VoiceCallStatus.active:
        if (isVideo) {
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              _RoundCallButton(
                icon: call.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: call.isMuted ? 'Bật mic' : 'Tắt mic',
                color: Colors.white24,
                onPressed: call.toggleMute,
                darkSurface: true,
                compact: true,
              ),
              _RoundCallButton(
                icon: call.cameraEnabled
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: call.cameraEnabled ? 'Tắt camera' : 'Bật camera',
                color: Colors.white24,
                onPressed: call.toggleCamera,
                darkSurface: true,
                compact: true,
              ),
              _RoundCallButton(
                icon: call.cameraSwitchPending
                    ? Icons.hourglass_top_rounded
                    : Icons.cameraswitch_rounded,
                label: 'Đổi camera',
                color: Colors.white24,
                onPressed: call.cameraSwitchPending ? null : call.switchCamera,
                darkSurface: true,
                compact: true,
              ),
              if (call.status == VoiceCallStatus.active)
                _RoundCallButton(
                  icon: chatOpen
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                  label: 'Chat & tệp',
                  color: chatOpen ? colors.primary : Colors.white24,
                  onPressed: onChatToggle,
                  darkSurface: true,
                  compact: true,
                ),
              _RoundCallButton(
                icon: Icons.call_end_rounded,
                label: 'Kết thúc',
                color: Theme.of(context).colorScheme.error,
                onPressed: call.hangUp,
                darkSurface: true,
                compact: true,
              ),
            ],
          );
        }
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 10,
          children: [
            _RoundCallButton(
              icon: call.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: call.isMuted ? 'Bật mic' : 'Tắt mic',
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              onPressed: call.toggleMute,
              compact: true,
            ),
            _RoundCallButton(
              icon: call.isSpeakerOn
                  ? Icons.volume_up_rounded
                  : Icons.hearing_rounded,
              label: 'Loa ngoài',
              color: call.isSpeakerOn
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: call.isSpeakerOn
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
              onPressed: call.toggleSpeaker,
              compact: true,
            ),
            if (call.status == VoiceCallStatus.active)
              _RoundCallButton(
                icon: chatOpen
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                label: 'Chat & tệp',
                color: chatOpen
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                foregroundColor: chatOpen
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
                onPressed: onChatToggle,
                compact: true,
              ),
            _RoundCallButton(
              icon: Icons.call_end_rounded,
              label: 'Kết thúc',
              color: Theme.of(context).colorScheme.error,
              onPressed: call.hangUp,
              compact: true,
            ),
          ],
        );
      case VoiceCallStatus.ended:
        return FilledButton.tonal(
          onPressed: call.operationPending ? null : call.dismissEnded,
          child: const Text('Đóng'),
        );
      case VoiceCallStatus.idle:
        return const SizedBox.shrink();
    }
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.foregroundColor = Colors.white,
    this.darkSurface = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foregroundColor;
  final FutureOr<void> Function()? onPressed;
  final bool darkSurface;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          child: IconButton.filled(
            onPressed: onPressed == null ? null : () => onPressed!(),
            icon: Icon(icon, size: compact ? 22 : 24),
            style: IconButton.styleFrom(
              backgroundColor: color,
              foregroundColor: foregroundColor,
              minimumSize: Size.square(compact ? 52 : 62),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: compact ? 68 : null,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: darkSurface ? Colors.white : null,
              fontSize: compact ? 10 : null,
            ),
          ),
        ),
      ],
    );
  }
}
