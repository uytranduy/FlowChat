import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config/app_config.dart';
import '../core/storage/token_storage.dart';
import '../models/user.dart';
import '../models/voice_call.dart';

class CallController extends ChangeNotifier {
  CallController(this._tokenStorage);

  static const _ackTimeout = Duration(seconds: 8);

  final TokenStorage _tokenStorage;
  io.Socket? _socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _queuedRemoteCandidates = [];
  Future<void> _signalQueue = Future.value();
  Timer? _durationTimer;
  Timer? _resetTimer;
  Timer? _connectionSetupTimer;
  Timer? _disconnectGraceTimer;
  Future<void>? _finishing;
  final Map<String, _EndedCallPayload> _earlyEndedCalls = {};
  final Set<String> _earlyAcceptedCalls = {};
  int _sessionVersion = 0;
  bool _serverAccepted = false;
  bool _terminationPending = false;
  bool _disposed = false;

  VoiceCallStatus status = VoiceCallStatus.idle;
  CallPeer? peer;
  String? callId;
  String? conversationId;
  String? errorMessage;
  String? endedReason;
  DateTime? activeSince;
  Duration elapsed = Duration.zero;
  CallMediaType mediaType = CallMediaType.audio;
  int endedDurationSeconds = 0;
  bool isCaller = false;
  bool isMuted = false;
  bool isSpeakerOn = false;
  bool cameraEnabled = false;
  bool isFrontCamera = true;
  bool cameraSwitchPending = false;
  bool socketConnected = false;
  bool operationPending = false;
  int _callHistoryRevision = 0;
  String? _callHistoryConversationId;
  int _friendRequestRevision = 0;
  String? _friendRequestSenderName;
  String? _friendRequestMessage;
  bool _friendRequestReceived = false;
  int _relationshipRevision = 0;
  Set<String> _onlineUserIds = const {};
  final Map<String, DateTime> _recentlyOfflineAt = {};
  int _conversationRevision = 0;
  int _messagePinRevision = 0;
  String? _messagePinConversationId;

  bool get isBusy => status != VoiceCallStatus.idle;
  bool get canStartCall => status == VoiceCallStatus.idle && socketConnected;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  int get callHistoryRevision => _callHistoryRevision;
  String? get callHistoryConversationId => _callHistoryConversationId;
  int get friendRequestRevision => _friendRequestRevision;
  String? get friendRequestSenderName => _friendRequestSenderName;
  String? get friendRequestMessage => _friendRequestMessage;
  bool get friendRequestReceived => _friendRequestReceived;
  int get relationshipRevision => _relationshipRevision;
  bool isUserOnline(String userId) => _onlineUserIds.contains(userId);
  DateTime? recentlyOfflineAt(String userId) => _recentlyOfflineAt[userId];
  int get conversationRevision => _conversationRevision;
  int get messagePinRevision => _messagePinRevision;
  String? get messagePinConversationId => _messagePinConversationId;

  Future<void> connect(User user) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null || token.trim().isEmpty || _disposed) return;

    await disconnect(notifyServer: false);
    if (_disposed) return;

    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .enableReconnection()
        .setReconnectionAttempts(20)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .setAuthFn((callback) {
          _tokenStorage.readAccessToken().then((latestToken) {
            callback({'token': latestToken?.trim() ?? ''});
          });
        })
        .build();

    final socket = io.io(AppConfig.socketBaseUrl, options);
    _socket = socket;
    socket.onConnect((_) {
      socketConnected = true;
      _notify();
    });
    socket.onDisconnect((_) {
      socketConnected = false;
      if (isBusy && status != VoiceCallStatus.ended) {
        unawaited(_finishLocally('disconnected'));
      } else {
        _notify();
      }
    });
    socket.onConnectError((_) {
      socketConnected = false;
      _notify();
    });
    socket.onReconnect((_) {
      socketConnected = true;
      _notify();
    });
    socket.on('call:incoming', _handleIncoming);
    socket.on('call:accepted', _handleAccepted);
    socket.on('call:signal', _handleSignalEvent);
    socket.on('call:ended', _handleEnded);
    socket.on('friend-request:received', _handleFriendRequestReceived);
    socket.on('friend-request:updated', _handleFriendRequestUpdated);
    socket.on('user-block:updated', _handleUserBlockUpdated);
    socket.on('online-users', _handleOnlineUsers);
    socket.on('new-group', _handleConversationUpdated);
    socket.on('conversation:updated', _handleConversationUpdated);
    socket.on('message-pin:updated', _handleMessagePinUpdated);
    socket.connect();
  }

  Future<void> disconnect({bool notifyServer = true}) async {
    if (notifyServer && isBusy) {
      await hangUp();
    } else {
      await _cleanupMedia();
      _resetState(notify: false);
    }

    final socket = _socket;
    _socket = null;
    socketConnected = false;
    _onlineUserIds = const {};
    _friendRequestReceived = false;
    _friendRequestSenderName = null;
    _friendRequestMessage = null;
    socket?.dispose();
    _notify();
  }

  Future<bool> startCall({
    required CallPeer callee,
    required String conversationId,
    CallMediaType mediaType = CallMediaType.audio,
  }) async {
    if (!canStartCall || callee.id.isEmpty || conversationId.isEmpty) {
      return false;
    }

    final version = ++_sessionVersion;
    _resetTimer?.cancel();
    _earlyEndedCalls.clear();
    _earlyAcceptedCalls.clear();
    peer = callee;
    this.conversationId = conversationId;
    this.mediaType = mediaType;
    isCaller = true;
    status = VoiceCallStatus.outgoing;
    errorMessage = null;
    endedReason = null;
    endedDurationSeconds = 0;
    _serverAccepted = false;
    operationPending = true;
    _notify();

    try {
      if (!await _openLocalMedia(version)) return false;
      final response = await _emitAck('call:start', {
        'calleeId': callee.id,
        'conversationId': conversationId,
        'mediaType': mediaType.value,
      });
      _ensureOk(response);
      final startedCallId = _string(response['callId']);
      if (startedCallId == null) {
        throw const CallException('Máy chủ không trả về mã cuộc gọi.');
      }
      if (version != _sessionVersion) {
        await _safeEmit('call:cancel', {'callId': startedCallId});
        return false;
      }
      final acknowledgedMediaType = _string(response['mediaType']);
      if (acknowledgedMediaType != null) {
        this.mediaType = CallMediaType.fromValue(acknowledgedMediaType);
      }
      callId = startedCallId;
      operationPending = false;
      final earlyEnd = _earlyEndedCalls.remove(startedCallId);
      final wasAcceptedEarly = _earlyAcceptedCalls.remove(startedCallId);
      _earlyEndedCalls.clear();
      _earlyAcceptedCalls.clear();
      if (earlyEnd != null) {
        if (earlyEnd.mediaType != null) this.mediaType = earlyEnd.mediaType!;
        await _finishLocally(
          earlyEnd.reason,
          durationSeconds: earlyEnd.durationSeconds,
        );
        return true;
      }
      _notify();
      if (wasAcceptedEarly) _applyAccepted(startedCallId);
      return true;
    } catch (error) {
      if (version != _sessionVersion) return false;
      final normalizedError =
          error is CallException && error.code == 'CALLEE_OFFLINE'
          ? CallException(
              loggedOutCallMessage(callee.displayName),
              code: error.code,
            )
          : error;
      await _fail(normalizedError, fallback: 'Không thể bắt đầu cuộc gọi.');
      return false;
    }
  }

  void _handleFriendRequestReceived(Object? data) {
    final payload = _map(data);
    final request = _map(payload['request']);
    final sender = _map(request['from']);
    _friendRequestSenderName =
        _string(sender['displayName']) ?? _string(sender['username']);
    _friendRequestMessage = _string(request['message']);
    _friendRequestReceived = true;
    _friendRequestRevision += 1;
    _notify();
  }

  void _handleFriendRequestUpdated(Object? _) {
    _friendRequestReceived = false;
    _friendRequestSenderName = null;
    _friendRequestMessage = null;
    _friendRequestRevision += 1;
    _notify();
  }

  void _handleUserBlockUpdated(Object? _) {
    _relationshipRevision += 1;
    _notify();
  }

  void _handleOnlineUsers(Object? data) {
    if (data is! List) return;
    final next = data.whereType<String>().toSet();
    final disconnected = _onlineUserIds.difference(next);
    final now = DateTime.now();
    for (final userId in disconnected) {
      _recentlyOfflineAt[userId] = now;
    }
    _onlineUserIds = next;
    _notify();
  }

  void _handleConversationUpdated(Object? _) {
    _conversationRevision += 1;
    _notify();
  }

  void _handleMessagePinUpdated(Object? data) {
    final payload = _map(data);
    final targetConversationId = _string(payload['conversationId']);
    if (targetConversationId == null || targetConversationId.isEmpty) return;
    _messagePinConversationId = targetConversationId;
    _messagePinRevision += 1;
    _notify();
  }

  Future<void> accept() async {
    final id = callId;
    if (status != VoiceCallStatus.incoming || id == null) return;
    final version = _sessionVersion;
    errorMessage = null;
    operationPending = true;
    _notify();

    try {
      if (!await _openLocalMedia(version)) return;
      await _ensurePeerConnection(version);
      if (version != _sessionVersion) return;
      final response = await _emitAck('call:accept', {'callId': id});
      _ensureOk(response);
      if (version != _sessionVersion) {
        await _safeEmit('call:end', {'callId': id, 'reason': 'ended'});
        return;
      }
      _serverAccepted = true;
      operationPending = false;
      status = VoiceCallStatus.connecting;
      _notify();
    } catch (error) {
      if (version != _sessionVersion) return;
      await _safeEmit('call:reject', {'callId': id, 'reason': 'media-error'});
      await _fail(
        error,
        fallback: mediaType.isVideo
            ? 'Không thể truy cập camera hoặc micrô.'
            : 'Không thể truy cập micrô.',
      );
    }
  }

  Future<void> reject() async {
    final id = callId;
    if (status != VoiceCallStatus.incoming ||
        id == null ||
        operationPending ||
        _terminationPending) {
      return;
    }
    final version = _sessionVersion;
    _terminationPending = true;
    try {
      await _safeEmit('call:reject', {'callId': id, 'reason': 'declined'});
      if (version == _sessionVersion && callId == id) {
        await _finishLocally('declined');
      }
    } finally {
      _terminationPending = false;
    }
  }

  Future<void> hangUp() async {
    final id = callId;
    final currentStatus = status;
    if (currentStatus == VoiceCallStatus.idle || _terminationPending) return;

    final version = _sessionVersion;
    _terminationPending = true;
    try {
      if (id != null && _socket?.connected == true) {
        if (!isCaller && !_serverAccepted) {
          await _safeEmit('call:reject', {'callId': id, 'reason': 'declined'});
        } else if (isCaller && !_serverAccepted) {
          await _safeEmit('call:cancel', {'callId': id});
        } else {
          await _safeEmit('call:end', {'callId': id, 'reason': 'ended'});
        }
      }
      if (version == _sessionVersion && callId == id) {
        await _finishLocally('ended');
      }
    } finally {
      _terminationPending = false;
    }
  }

  void toggleMute() {
    if (_localStream == null) return;
    isMuted = !isMuted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !isMuted;
    }
    _notify();
  }

  void toggleCamera() {
    if (!mediaType.isVideo || _localStream == null) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isEmpty) return;
    cameraEnabled = !cameraEnabled;
    for (final track in tracks) {
      track.enabled = cameraEnabled;
    }
    _notify();
  }

  Future<void> switchCamera() async {
    if (!mediaType.isVideo || _localStream == null || cameraSwitchPending) {
      return;
    }
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isEmpty) return;

    cameraSwitchPending = true;
    _notify();
    try {
      final switched = await Helper.switchCamera(tracks.first);
      if (switched) isFrontCamera = !isFrontCamera;
    } catch (_) {
      // Keep the current camera when the device only exposes one lens.
    } finally {
      cameraSwitchPending = false;
      _notify();
    }
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn = !isSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(isSpeakerOn);
    } catch (_) {
      isSpeakerOn = !isSpeakerOn;
    }
    _notify();
  }

  void dismissEnded() {
    if (status != VoiceCallStatus.ended) return;
    _resetState();
  }

  void _handleIncoming(dynamic data) {
    final payload = _map(data);
    final incomingCallId = _string(payload['callId']);
    final incomingConversationId = _string(payload['conversationId']);
    final caller = _map(payload['caller']);
    if (incomingCallId == null || incomingConversationId == null) return;

    if (status != VoiceCallStatus.idle) {
      unawaited(
        _safeEmit('call:reject', {'callId': incomingCallId, 'reason': 'busy'}),
      );
      return;
    }

    _resetTimer?.cancel();
    _sessionVersion += 1;
    callId = incomingCallId;
    conversationId = incomingConversationId;
    peer = CallPeer.fromJson(caller);
    mediaType = CallMediaType.fromValue(payload['mediaType']);
    isCaller = false;
    status = VoiceCallStatus.incoming;
    errorMessage = null;
    endedReason = null;
    endedDurationSeconds = 0;
    _serverAccepted = false;
    _notify();
  }

  void _handleAccepted(dynamic data) {
    final payload = _map(data);
    final acceptedCallId = _string(payload['callId']);
    if (acceptedCallId == null) return;
    final acceptedMediaType = _string(payload['mediaType']);
    if (callId == null && status == VoiceCallStatus.outgoing) {
      _earlyAcceptedCalls.add(acceptedCallId);
      return;
    }
    if (acceptedCallId == callId && acceptedMediaType != null) {
      mediaType = CallMediaType.fromValue(acceptedMediaType);
    }
    _applyAccepted(acceptedCallId);
  }

  void _applyAccepted(String acceptedCallId) {
    if (acceptedCallId != callId || status != VoiceCallStatus.outgoing) {
      return;
    }
    _serverAccepted = true;
    operationPending = false;
    status = VoiceCallStatus.connecting;
    _notify();
    unawaited(_createAndSendOffer(_sessionVersion));
  }

  void _handleSignalEvent(dynamic data) {
    final payload = _map(data);
    final signalCallId = _string(payload['callId']);
    if (signalCallId != callId) return;
    final signal = _map(payload['signal']);
    _signalQueue = _signalQueue
        .then((_) async {
          if (callId != signalCallId) return;
          await _processSignal(signal);
        })
        .catchError((Object error) async {
          if (callId == signalCallId) {
            await _fail(
              error,
              fallback: 'Không thể thiết lập kết nối thoại.',
              reason: 'connection-failed',
            );
          }
        });
  }

  void _handleEnded(dynamic data) {
    final payload = _map(data);
    final endedCallId = _string(payload['callId']);
    if (endedCallId == null) return;
    final reason = _string(payload['reason']) ?? 'ended';
    final durationSeconds = _int(payload['durationSeconds']);
    final endedConversationId =
        _string(payload['conversationId']) ?? conversationId;
    final endedMediaType = _string(payload['mediaType']) == null
        ? null
        : CallMediaType.fromValue(payload['mediaType']);
    if (callId == null && status == VoiceCallStatus.outgoing) {
      _earlyEndedCalls[endedCallId] = _EndedCallPayload(
        reason: reason,
        durationSeconds: durationSeconds,
        mediaType: endedMediaType,
      );
      _signalCallHistoryRefresh(endedConversationId);
      return;
    }
    if (endedCallId != callId) return;
    if (endedMediaType != null) mediaType = endedMediaType;
    _signalCallHistoryRefresh(endedConversationId);
    unawaited(_finishLocally(reason, durationSeconds: durationSeconds));
  }

  void _signalCallHistoryRefresh(String? targetConversationId) {
    if (targetConversationId == null || targetConversationId.isEmpty) return;
    _callHistoryConversationId = targetConversationId;
    _callHistoryRevision += 1;
    _notify();
  }

  Future<void> _createAndSendOffer(int version) async {
    try {
      final pc = await _ensurePeerConnection(version);
      if (version != _sessionVersion) return;
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': mediaType.isVideo,
      });
      if (version != _sessionVersion) return;
      await pc.setLocalDescription(offer);
      if (version != _sessionVersion) return;
      final sdp = normalizeSessionDescriptionSdp(offer.sdp);
      if (sdp == null) {
        throw const CallException('Không thể tạo mô tả kết nối thoại.');
      }
      await _sendSignal({'type': 'offer', 'sdp': sdp});
    } catch (error) {
      if (version != _sessionVersion) return;
      await _fail(
        error,
        fallback: 'Không thể tạo kết nối thoại.',
        reason: 'connection-failed',
      );
    }
  }

  Future<void> _processSignal(Map<String, dynamic> signal) async {
    if (callId == null ||
        (status != VoiceCallStatus.connecting &&
            status != VoiceCallStatus.active)) {
      return;
    }

    final version = _sessionVersion;
    final type = _string(signal['type']);
    if (type == 'ice-candidate') {
      final candidateValue = _string(signal['candidate']);
      if (candidateValue == null) return;
      final candidate = RTCIceCandidate(
        candidateValue,
        _string(signal['sdpMid']),
        _int(signal['sdpMLineIndex']),
      );
      final pc = await _ensurePeerConnection(version);
      if (version != _sessionVersion) return;
      if (await pc.getRemoteDescription() == null) {
        _queuedRemoteCandidates.add(candidate);
      } else {
        await pc.addCandidate(candidate);
      }
      return;
    }

    // SDP is line based and libwebrtc requires the final line terminator.
    // Do not pass it through `_string`, which trims the trailing CRLF.
    final sdp = normalizeSessionDescriptionSdp(signal['sdp']);
    if ((type != 'offer' && type != 'answer') || sdp == null) return;
    final pc = await _ensurePeerConnection(version);
    if (version != _sessionVersion) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    if (version != _sessionVersion) return;
    await _drainRemoteCandidates(pc);

    if (type == 'offer') {
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': mediaType.isVideo,
      });
      if (version != _sessionVersion) return;
      await pc.setLocalDescription(answer);
      if (version != _sessionVersion) return;
      final answerSdp = normalizeSessionDescriptionSdp(answer.sdp);
      if (answerSdp == null) {
        throw const CallException('Không thể tạo mô tả kết nối thoại.');
      }
      await _sendSignal({'type': 'answer', 'sdp': answerSdp});
    }
  }

  Future<RTCPeerConnection> _ensurePeerConnection(int version) async {
    final existing = _peerConnection;
    if (existing != null) return existing;

    final pc = await createPeerConnection({
      'iceServers': AppConfig.webRtcIceServers,
      'sdpSemantics': 'unified-plan',
    });
    if (version != _sessionVersion) {
      await pc.close();
      await pc.dispose();
      throw const CallException('Cuộc gọi đã được hủy.', code: 'canceled');
    }
    _peerConnection = pc;
    final connectionCallId = callId;
    if (connectionCallId == null) {
      await pc.close();
      await pc.dispose();
      _peerConnection = null;
      throw const CallException('Cuộc gọi không còn tồn tại.');
    }
    _startConnectionSetupTimer(version, connectionCallId);

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
        if (version != _sessionVersion) {
          throw const CallException('Cuộc gọi đã được hủy.', code: 'canceled');
        }
      }
    }

    pc.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null ||
          value.isEmpty ||
          version != _sessionVersion ||
          callId != connectionCallId) {
        return;
      }
      unawaited(
        _sendSignal({
          'type': 'ice-candidate',
          'candidate': value,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }, waitForAck: false),
      );
    };
    pc.onTrack = (event) {
      if (version == _sessionVersion &&
          callId == connectionCallId &&
          event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _notify();
      }
    };
    pc.onConnectionState = (state) {
      if (version != _sessionVersion || callId != connectionCallId) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectionSetupTimer?.cancel();
        _connectionSetupTimer = null;
        _disconnectGraceTimer?.cancel();
        _disconnectGraceTimer = null;
        _markActive();
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _startDisconnectGraceTimer(version, connectionCallId, pc);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_handleConnectionFailure(version, connectionCallId));
      }
    };
    return pc;
  }

  Future<bool> _openLocalMedia(int version) async {
    if (_localStream != null) return version == _sessionVersion;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': mediaType.isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30},
            }
          : false,
    });
    if (version != _sessionVersion) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      return false;
    }
    _localStream = stream;
    for (final track in stream.getAudioTracks()) {
      track.enabled = true;
    }
    for (final track in stream.getVideoTracks()) {
      track.enabled = true;
    }
    isMuted = false;
    cameraEnabled = mediaType.isVideo && stream.getVideoTracks().isNotEmpty;
    isFrontCamera = true;
    isSpeakerOn = mediaType.isVideo;
    try {
      await Helper.setSpeakerphoneOn(isSpeakerOn);
    } catch (_) {
      // Some desktop targets do not expose native audio routing.
    }
    return version == _sessionVersion;
  }

  Future<void> _drainRemoteCandidates(RTCPeerConnection pc) async {
    final candidates = List<RTCIceCandidate>.from(_queuedRemoteCandidates);
    _queuedRemoteCandidates.clear();
    for (final candidate in candidates) {
      await pc.addCandidate(candidate);
    }
  }

  void _startConnectionSetupTimer(int version, String expectedCallId) {
    _connectionSetupTimer?.cancel();
    _connectionSetupTimer = Timer(const Duration(seconds: 30), () {
      if (version == _sessionVersion &&
          callId == expectedCallId &&
          status == VoiceCallStatus.connecting) {
        unawaited(_handleConnectionFailure(version, expectedCallId));
      }
    });
  }

  void _startDisconnectGraceTimer(
    int version,
    String expectedCallId,
    RTCPeerConnection connection,
  ) {
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = Timer(const Duration(seconds: 10), () {
      if (version == _sessionVersion &&
          callId == expectedCallId &&
          identical(_peerConnection, connection) &&
          connection.connectionState !=
              RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        unawaited(_handleConnectionFailure(version, expectedCallId));
      }
    });
  }

  Future<void> _sendSignal(
    Map<String, dynamic> signal, {
    bool waitForAck = true,
  }) async {
    final id = callId;
    if (id == null) return;
    final payload = {'callId': id, 'signal': signal};
    if (waitForAck) {
      final response = await _emitAck('call:signal', payload);
      _ensureOk(response);
    } else {
      _socket?.emit('call:signal', payload);
    }
  }

  Future<Map<String, dynamic>> _emitAck(
    String event,
    Map<String, dynamic> payload,
  ) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const CallException('Mất kết nối tới máy chủ cuộc gọi.');
    }
    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(
      event,
      payload,
      ack: (dynamic response) {
        if (!completer.isCompleted) completer.complete(_map(response));
      },
    );
    return completer.future.timeout(
      _ackTimeout,
      onTimeout: () => throw const CallException(
        'Máy chủ cuộc gọi không phản hồi.',
        code: 'timeout',
      ),
    );
  }

  Future<void> _safeEmit(String event, Map<String, dynamic> payload) async {
    try {
      await _emitAck(event, payload);
    } catch (_) {
      // Cleanup locally even when signaling is already disconnected.
    }
  }

  static void _ensureOk(Map<String, dynamic> response) {
    if (response['ok'] == true) return;
    final error = _map(response['error']);
    throw CallException(
      _string(error['message']) ?? 'Yêu cầu cuộc gọi thất bại.',
      code: _string(error['code']),
    );
  }

  void _markActive() {
    if (status == VoiceCallStatus.active) return;
    status = VoiceCallStatus.active;
    activeSince = DateTime.now();
    elapsed = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final since = activeSince;
      if (since == null) return;
      elapsed = DateTime.now().difference(since);
      _notify();
    });
    _notify();
  }

  Future<void> _fail(
    Object error, {
    required String fallback,
    String reason = 'media-error',
  }) async {
    final version = _sessionVersion;
    final message = error is CallException ? error.message : fallback;
    errorMessage = message;
    final id = callId;
    if (id != null) {
      await _safeEmit('call:end', {'callId': id, 'reason': reason});
    }
    if (version == _sessionVersion && callId == id) {
      await _finishLocally(reason);
    }
  }

  Future<void> _handleConnectionFailure(
    int version,
    String expectedCallId,
  ) async {
    if (version != _sessionVersion || callId != expectedCallId) return;
    final id = callId;
    if (id != null) {
      await _safeEmit('call:end', {
        'callId': id,
        'reason': 'connection-failed',
      });
    }
    if (version == _sessionVersion && callId == expectedCallId) {
      await _finishLocally('connection-failed');
    }
  }

  Future<void> _finishLocally(String reason, {int? durationSeconds}) async {
    if (status == VoiceCallStatus.ended) {
      endedReason = reason;
      if (durationSeconds != null) {
        endedDurationSeconds = durationSeconds;
      }
      _notify();
      final finishing = _finishing;
      if (finishing != null) await finishing;
      return;
    }
    final finishVersion = ++_sessionVersion;
    final finishedCallId = callId;
    endedReason = reason;
    endedDurationSeconds = durationSeconds ?? elapsed.inSeconds;
    status = VoiceCallStatus.ended;
    operationPending = true;
    _notify();

    late final Future<void> finishing;
    finishing = _cleanupMedia()
        .then((_) {
          if (finishVersion == _sessionVersion &&
              status == VoiceCallStatus.ended &&
              callId == finishedCallId) {
            operationPending = false;
            _notify();
            _resetTimer?.cancel();
            _resetTimer = Timer(const Duration(seconds: 3), () {
              if (finishVersion == _sessionVersion &&
                  status == VoiceCallStatus.ended &&
                  callId == finishedCallId) {
                _resetState();
              }
            });
          }
        })
        .whenComplete(() {
          if (identical(_finishing, finishing)) _finishing = null;
        });
    _finishing = finishing;
    await finishing;
  }

  Future<void> _cleanupMedia() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectionSetupTimer?.cancel();
    _connectionSetupTimer = null;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    activeSince = null;
    elapsed = Duration.zero;
    _queuedRemoteCandidates.clear();

    final pc = _peerConnection;
    final localStream = _localStream;
    final remoteStream = _remoteStream;
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    cameraEnabled = false;
    cameraSwitchPending = false;
    if (pc != null) {
      try {
        pc.onConnectionState = null;
        pc.onIceConnectionState = null;
        pc.onIceCandidate = null;
        pc.onTrack = null;
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }

    final streams = <MediaStream>[?localStream];
    if (remoteStream != null && !identical(remoteStream, localStream)) {
      streams.add(remoteStream);
    }
    for (final stream in streams) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
    try {
      await Helper.setSpeakerphoneOn(false);
      await Helper.clearAndroidCommunicationDevice();
    } catch (_) {}
  }

  void _resetState({bool notify = true}) {
    _sessionVersion += 1;
    _resetTimer?.cancel();
    _resetTimer = null;
    _connectionSetupTimer?.cancel();
    _connectionSetupTimer = null;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    _earlyEndedCalls.clear();
    _earlyAcceptedCalls.clear();
    status = VoiceCallStatus.idle;
    peer = null;
    callId = null;
    conversationId = null;
    errorMessage = null;
    endedReason = null;
    endedDurationSeconds = 0;
    activeSince = null;
    elapsed = Duration.zero;
    mediaType = CallMediaType.audio;
    isCaller = false;
    isMuted = false;
    isSpeakerOn = false;
    cameraEnabled = false;
    isFrontCamera = true;
    cameraSwitchPending = false;
    _serverAccepted = false;
    operationPending = false;
    _terminationPending = false;
    if (notify) _notify();
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  /// Preserves the SDP payload verbatim and restores its required final line
  /// terminator when a non-WebRTC transport omitted it.
  static String? normalizeSessionDescriptionSdp(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    if (value.endsWith('\n')) return value;
    if (value.endsWith('\r')) return '$value\n';
    return '$value\r\n';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionVersion += 1;
    _durationTimer?.cancel();
    _resetTimer?.cancel();
    _connectionSetupTimer?.cancel();
    _disconnectGraceTimer?.cancel();
    _socket?.dispose();
    unawaited(_cleanupMedia());
    super.dispose();
  }
}

class _EndedCallPayload {
  const _EndedCallPayload({
    required this.reason,
    this.durationSeconds,
    this.mediaType,
  });

  final String reason;
  final int? durationSeconds;
  final CallMediaType? mediaType;
}
