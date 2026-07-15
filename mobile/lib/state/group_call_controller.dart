import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config/app_config.dart';
import '../core/storage/token_storage.dart';
import '../models/user.dart';
import '../models/voice_call.dart';

enum GroupCallStatus { idle, incoming, joining, active }

class GroupCallMember {
  const GroupCallMember({
    required this.userId,
    required this.socketId,
    required this.displayName,
    this.avatarUrl,
    this.isCaller = false,
  });
  factory GroupCallMember.fromJson(Map<String, dynamic> json) =>
      GroupCallMember(
        userId: '${json['userId'] ?? json['id'] ?? ''}',
        socketId: '${json['socketId'] ?? ''}',
        displayName: '${json['displayName'] ?? 'Thành viên'}',
        avatarUrl: json['avatarUrl']?.toString(),
        isCaller: json['isCaller'] == true,
      );
  final String userId;
  final String socketId;
  final String displayName;
  final String? avatarUrl;
  final bool isCaller;
}

class GroupCallController extends ChangeNotifier {
  GroupCallController(this._tokens);
  final TokenStorage _tokens;
  io.Socket? _socket;
  User? _me;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};
  MediaStream? _localStream;
  final Map<String, MediaStream> remoteStreams = {};

  GroupCallStatus status = GroupCallStatus.idle;
  String? callId;
  String? conversationId;
  String groupName = 'Nhóm chat';
  CallMediaType mediaType = CallMediaType.audio;
  GroupCallMember? caller;
  List<GroupCallMember> participants = const [];
  bool muted = false;
  bool cameraEnabled = false;
  bool socketConnected = false;
  String? availableCallId;
  String? availableConversationId;
  CallMediaType? availableMediaType;
  int availableParticipantCount = 0;

  MediaStream? get localStream => _localStream;
  String? get currentUserId => _me?.id;
  bool get isBusy => status != GroupCallStatus.idle;
  bool get canStart => !isBusy && socketConnected;
  bool canRejoin(String targetConversationId) =>
      status == GroupCallStatus.idle &&
      availableCallId != null &&
      availableConversationId == targetConversationId &&
      availableParticipantCount > 0;

  Future<void> checkActive(String targetConversationId) async {
    if (!socketConnected || isBusy || targetConversationId.trim().isEmpty) {
      return;
    }
    try {
      final response = await _ack('group-call:get-active', {
        'conversationId': targetConversationId,
      });
      if (response['active'] != true) {
        if (availableConversationId == targetConversationId) {
          availableCallId = null;
          availableConversationId = null;
          availableMediaType = null;
          availableParticipantCount = 0;
          notifyListeners();
        }
        return;
      }

      final activeCall = _map(response['call']);
      final activeCallId = _text(activeCall['callId']);
      if (activeCallId == null) return;
      availableCallId = activeCallId;
      availableConversationId = targetConversationId;
      availableMediaType = CallMediaType.fromValue(activeCall['mediaType']);
      availableParticipantCount =
          int.tryParse('${activeCall['participantCount']}') ?? 0;
      notifyListeners();
    } catch (_) {
      // Socket có thể đang kết nối lại; lần polling tiếp theo sẽ thử lại.
    }
  }

  Future<void> connect(User user) async {
    _me = user;
    final token = await _tokens.readAccessToken();
    if (token == null) return;
    await disconnect();
    _me = user;
    final socket = io.io(
      AppConfig.socketBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .setAuth({'token': token})
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) {
      socketConnected = true;
      notifyListeners();
    });
    socket.onDisconnect((_) {
      socketConnected = false;
      if (isBusy) _reset(clearAvailable: true);
      notifyListeners();
    });
    socket.on('group-call:incoming', _incoming);
    socket.on('group-call:active', _activeRoomUpdated);
    socket.on('group-call:participant-joined', _participantJoined);
    socket.on('group-call:participant-left', _participantLeft);
    socket.on('group-call:signal', _signal);
    socket.on('group-call:ended', (_) => _reset(clearAvailable: true));
    socket.on('group-call:dismissed', (_) => _reset());
    socket.connect();
  }

  Future<void> disconnect() async {
    if (isBusy) await leave();
    _socket?.dispose();
    _socket = null;
    socketConnected = false;
    _reset(clearAvailable: true);
  }

  Future<bool> start({
    required String conversationId,
    required String name,
    required CallMediaType mediaType,
  }) async {
    if (!canStart) return false;
    try {
      final activeResponse = await _ack('group-call:get-active', {
        'conversationId': conversationId,
      });
      if (activeResponse['active'] == true) {
        final activeCall = _map(activeResponse['call']);
        final activeCallId = _text(activeCall['callId']);
        if (activeCallId != null) {
          callId = activeCallId;
          this.conversationId = conversationId;
          groupName = _text(_map(activeCall['conversation'])['name']) ?? name;
          this.mediaType = CallMediaType.fromValue(activeCall['mediaType']);
          availableCallId = activeCallId;
          availableConversationId = conversationId;
          availableMediaType = this.mediaType;
          availableParticipantCount =
              int.tryParse('${activeCall['participantCount']}') ?? 0;
          status = GroupCallStatus.incoming;
          notifyListeners();
          await join();
          return status == GroupCallStatus.active;
        }
      }

      status = GroupCallStatus.joining;
      this.conversationId = conversationId;
      groupName = name;
      this.mediaType = mediaType;
      notifyListeners();
      await _openMedia();
      final response = await _ack('group-call:start', {
        'conversationId': conversationId,
        'mediaType': mediaType.value,
      });
      callId = _text(response['callId']);
      if (callId == null) {
        throw const CallException('Máy chủ không trả về mã cuộc gọi nhóm.');
      }
      participants = _members(response['participants']);
      availableCallId = callId;
      availableConversationId = conversationId;
      availableMediaType = mediaType;
      availableParticipantCount = participants.length;
      status = GroupCallStatus.active;
      notifyListeners();
      return true;
    } catch (_) {
      await _cleanup();
      _reset();
      return false;
    }
  }

  Future<void> join() async {
    final id = callId;
    if (status != GroupCallStatus.incoming || id == null) return;
    status = GroupCallStatus.joining;
    notifyListeners();
    try {
      await _openMedia();
      final response = await _ack('group-call:join', {'callId': id});
      participants = _members(response['participants']);
      availableCallId = id;
      availableConversationId = conversationId;
      availableMediaType = mediaType;
      availableParticipantCount = participants.length;
      status = GroupCallStatus.active;
      notifyListeners();
      for (final member in participants) {
        if (member.userId != _me?.id && member.socketId.isNotEmpty) {
          await _offer(member);
        }
      }
    } catch (_) {
      await _cleanup();
      _reset();
    }
  }

  void dismiss() => _reset();

  Future<void> leave() async {
    final id = callId;
    if (id != null && conversationId != null) {
      availableCallId = id;
      availableConversationId = conversationId;
      availableMediaType = mediaType;
      availableParticipantCount = participants.length > 1
          ? participants.length - 1
          : 0;
    }
    await _cleanup();
    _reset();
    if (id != null) {
      try {
        await _ack('group-call:leave', {'callId': id, 'reason': 'left'});
      } catch (_) {}
    }
  }

  void toggleMute() {
    muted = !muted;
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    cameraEnabled = !cameraEnabled;
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = cameraEnabled;
    }
    notifyListeners();
  }

  void _incoming(dynamic value) {
    if (isBusy) return;
    final data = _map(value);
    if (data['canJoin'] == false) return;
    final rawCaller = _map(data['caller']);
    final conversation = _map(data['conversation']);
    callId = _text(data['callId']);
    conversationId = _text(data['conversationId']);
    if (callId == null || conversationId == null) return;
    groupName = _text(conversation['name']) ?? 'Nhóm chat';
    mediaType = CallMediaType.fromValue(data['mediaType']);
    availableCallId = callId;
    availableConversationId = conversationId;
    availableMediaType = mediaType;
    availableParticipantCount =
        int.tryParse('${data['participantCount']}') ?? 1;
    caller = GroupCallMember(
      userId: _text(rawCaller['id']) ?? '',
      socketId: '',
      displayName: _text(rawCaller['displayName']) ?? 'Thành viên',
      avatarUrl: _text(rawCaller['avatarUrl']),
    );
    status = GroupCallStatus.incoming;
    notifyListeners();
  }

  void _participantJoined(dynamic value) {
    final data = _map(value);
    if (_text(data['callId']) == availableCallId) {
      availableParticipantCount =
          int.tryParse('${data['participantCount']}') ??
          availableParticipantCount + 1;
    }
    if (_text(data['callId']) != callId) return;
    final member = GroupCallMember.fromJson(_map(data['participant']));
    participants = [
      ...participants.where((item) => item.userId != member.userId),
      member,
    ];
    notifyListeners();
  }

  void _participantLeft(dynamic value) {
    final data = _map(value);
    if (_text(data['callId']) == availableCallId) {
      availableParticipantCount =
          int.tryParse('${data['participantCount']}') ?? 0;
      notifyListeners();
    }
    if (_text(data['callId']) != callId) return;
    final departed = _map(data['participant']);
    final socketId = _text(departed['socketId'] ?? data['socketId']) ?? '';
    final userId = _text(departed['userId'] ?? data['userId']) ?? '';
    _peers.remove(socketId)?.dispose();
    remoteStreams.remove(userId)?.dispose();
    participants = participants
        .where((item) => item.userId != userId)
        .toList(growable: false);
    notifyListeners();
  }

  void _signal(dynamic value) {
    unawaited(_processSignal(_map(value)));
  }

  void _activeRoomUpdated(dynamic value) {
    final data = _map(value);
    final id = _text(data['callId']);
    final conversation = _text(data['conversationId']);
    if (id == null || conversation == null) return;
    availableCallId = id;
    availableConversationId = conversation;
    availableMediaType = CallMediaType.fromValue(data['mediaType']);
    availableParticipantCount =
        int.tryParse('${data['participantCount']}') ??
        availableParticipantCount;
    notifyListeners();
  }

  Future<void> _processSignal(Map<String, dynamic> data) async {
    if (_text(data['callId']) != callId) return;
    final fromSocket = _text(data['fromSocketId']);
    final fromUser = _text(data['fromUserId']);
    if (fromSocket == null || fromUser == null) return;
    final member =
        participants.where((item) => item.socketId == fromSocket).firstOrNull ??
        GroupCallMember(
          userId: fromUser,
          socketId: fromSocket,
          displayName: 'Thành viên',
        );
    final pc = await _peer(member);
    final signal = _map(data['signal']);
    final type = _text(signal['type']);
    if (type == 'ice-candidate') {
      final candidate = RTCIceCandidate(
        _text(signal['candidate']),
        _text(signal['sdpMid']),
        int.tryParse('${signal['sdpMLineIndex']}'),
      );
      if (await pc.getRemoteDescription() == null) {
        (_pendingIce[fromSocket] ??= []).add(candidate);
      } else {
        await pc.addCandidate(candidate);
      }
      return;
    }
    final sdp = signal['sdp']?.toString();
    if (sdp == null || (type != 'offer' && type != 'answer')) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    for (final candidate
        in _pendingIce.remove(fromSocket) ?? const <RTCIceCandidate>[]) {
      await pc.addCandidate(candidate);
    }
    if (type == 'offer') {
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _relay(fromSocket, {'type': 'answer', 'sdp': answer.sdp});
    }
  }

  Future<void> _offer(GroupCallMember member) async {
    final pc = await _peer(member);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _relay(member.socketId, {'type': 'offer', 'sdp': offer.sdp});
  }

  Future<RTCPeerConnection> _peer(GroupCallMember member) async {
    final existing = _peers[member.socketId];
    if (existing != null) return existing;
    final pc = await createPeerConnection({
      'iceServers': AppConfig.webRtcIceServers,
      'sdpSemantics': 'unified-plan',
    });
    _peers[member.socketId] = pc;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(track, _localStream!);
    }
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate?.isNotEmpty == true) {
        unawaited(
          _relay(member.socketId, {
            'type': 'ice-candidate',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }, wait: false),
        );
      }
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStreams[member.userId] = event.streams.first;
        notifyListeners();
      }
    };
    return pc;
  }

  Future<void> _relay(
    String targetSocketId,
    Map<String, dynamic> signal, {
    bool wait = true,
  }) async {
    final payload = {
      'callId': callId,
      'targetSocketId': targetSocketId,
      'signal': signal,
    };
    if (wait) {
      await _ack('group-call:signal', payload);
    } else {
      _socket?.emit('group-call:signal', payload);
    }
  }

  Future<void> _openMedia() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': mediaType.isVideo ? {'facingMode': 'user'} : false,
    });
    cameraEnabled = mediaType.isVideo;
    muted = false;
  }

  Future<void> _cleanup() async {
    for (final pc in _peers.values) {
      await pc.close();
      await pc.dispose();
    }
    _peers.clear();
    _pendingIce.clear();
    for (final stream in <MediaStream>[
      ?_localStream,
      ...remoteStreams.values,
    ]) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    _localStream = null;
    remoteStreams.clear();
  }

  void _reset({bool clearAvailable = false}) {
    status = GroupCallStatus.idle;
    callId = null;
    conversationId = null;
    groupName = 'Nhóm chat';
    caller = null;
    participants = const [];
    muted = false;
    cameraEnabled = false;
    if (clearAvailable) {
      availableCallId = null;
      availableConversationId = null;
      availableMediaType = null;
      availableParticipantCount = 0;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> _ack(
    String event,
    Map<String, dynamic> payload,
  ) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const CallException('Mất kết nối máy chủ cuộc gọi.');
    }
    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(
      event,
      payload,
      ack: (value) => completer.complete(_map(value)),
    );
    final response = await completer.future.timeout(const Duration(seconds: 8));
    if (response['ok'] != true) {
      throw CallException(
        _text(_map(response['error'])['message']) ??
            'Yêu cầu cuộc gọi nhóm thất bại.',
      );
    }
    return response;
  }

  static List<GroupCallMember> _members(dynamic value) => value is List
      ? value
            .map((item) => GroupCallMember.fromJson(_map(item)))
            .toList(growable: false)
      : const [];
  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? value.map((key, item) => MapEntry('$key', item))
      : const {};
  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  @override
  void dispose() {
    _socket?.dispose();
    unawaited(_cleanup());
    super.dispose();
  }
}
