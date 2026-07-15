import { create } from "zustand";
import { toast } from "sonner";

import { useSocketStore } from "./useSocketStore";
import type {
  AcceptedCallPayload,
  CallMediaType,
  CallPeer,
  CallSignal,
  CallSignalPayload,
  CallState,
  EndedCallPayload,
  IceCandidateSignal,
  IncomingCallPayload,
} from "@/types/call";

const ACK_TIMEOUT_MS = 8_000;
const DISCONNECT_GRACE_MS = 10_000;
const CONNECTION_SETUP_TIMEOUT_MS = 30_000;
const DEFAULT_STUN_URL = "stun:stun.l.google.com:19302";

let peerConnection: RTCPeerConnection | null = null;
let localStream: MediaStream | null = null;
let remoteMediaStream: MediaStream | null = null;
let pendingIceCandidates: RTCIceCandidateInit[] = [];
let signalQueue: Promise<void> = Promise.resolve();
let disconnectTimer: ReturnType<typeof setTimeout> | null = null;
let connectionSetupTimer: ReturnType<typeof setTimeout> | null = null;
let sessionVersion = 0;

class CallOperationError extends Error {
  code: string;

  constructor(message: string, code = "CALL_ERROR") {
    super(message);
    this.name = "CallOperationError";
    this.code = code;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function readString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function readMediaType(value: unknown): CallMediaType | null {
  return value === "audio" || value === "video" ? value : null;
}

function parseIncomingCall(payload: unknown): IncomingCallPayload | null {
  if (!isRecord(payload) || !isRecord(payload.caller)) return null;

  const callId = readString(payload.callId);
  const conversationId = readString(payload.conversationId);
  const callerId = readString(payload.caller.id);
  const displayName = readString(payload.caller.displayName);
  const createdAt = readString(payload.createdAt);
  const mediaType = readMediaType(payload.mediaType);

  if (
    !callId ||
    !conversationId ||
    !callerId ||
    !displayName ||
    !createdAt ||
    !mediaType ||
    typeof payload.timeoutMs !== "number"
  ) {
    return null;
  }

  const avatarUrl =
    typeof payload.caller.avatarUrl === "string" ||
    payload.caller.avatarUrl === null
      ? payload.caller.avatarUrl
      : null;

  return {
    callId,
    conversationId,
    caller: { id: callerId, displayName, avatarUrl },
    mediaType,
    createdAt,
    timeoutMs: payload.timeoutMs,
  };
}

function parseAcceptedCall(payload: unknown): AcceptedCallPayload | null {
  if (!isRecord(payload)) return null;

  const callId = readString(payload.callId);
  const acceptedAt = readString(payload.acceptedAt);
  const mediaType = readMediaType(payload.mediaType);
  return callId && acceptedAt && mediaType
    ? { callId, acceptedAt, mediaType }
    : null;
}

function parseEndedCall(payload: unknown): EndedCallPayload | null {
  if (!isRecord(payload)) return null;

  const callId = readString(payload.callId);
  const conversationId = readString(payload.conversationId);
  const reason = readString(payload.reason);
  const mediaType = readMediaType(payload.mediaType);
  const durationSeconds = payload.durationSeconds;
  return callId &&
    reason &&
    mediaType &&
    typeof durationSeconds === "number" &&
    Number.isFinite(durationSeconds) &&
    durationSeconds >= 0
    ? {
        callId,
        ...(conversationId ? { conversationId } : {}),
        reason,
        mediaType,
        durationSeconds,
      }
    : null;
}

function parseCallSignal(payload: unknown): CallSignalPayload | null {
  if (!isRecord(payload) || !isRecord(payload.signal)) return null;

  const callId = readString(payload.callId);
  const type = payload.signal.type;
  if (!callId) return null;

  if (type === "offer" || type === "answer") {
    const sdp = readString(payload.signal.sdp);
    return sdp ? { callId, signal: { type, sdp } } : null;
  }

  if (type === "ice-candidate" && typeof payload.signal.candidate === "string") {
    const candidate: IceCandidateSignal = {
      type,
      candidate: payload.signal.candidate,
    };

    if (
      typeof payload.signal.sdpMid === "string" ||
      payload.signal.sdpMid === null
    ) {
      candidate.sdpMid = payload.signal.sdpMid;
    }

    if (
      typeof payload.signal.sdpMLineIndex === "number" ||
      payload.signal.sdpMLineIndex === null
    ) {
      candidate.sdpMLineIndex = payload.signal.sdpMLineIndex;
    }

    return { callId, signal: candidate };
  }

  return null;
}

function successfulAck(response: unknown): Record<string, unknown> {
  if (!isRecord(response)) {
    throw new CallOperationError("Máy chủ không phản hồi hợp lệ.", "INVALID_ACK");
  }

  if (response.ok === true) return response;

  if (response.ok === false && isRecord(response.error)) {
    const message = readString(response.error.message) ?? "Không thể thực hiện cuộc gọi.";
    const code = readString(response.error.code) ?? "CALL_ERROR";
    throw new CallOperationError(message, code);
  }

  throw new CallOperationError("Máy chủ không phản hồi hợp lệ.", "INVALID_ACK");
}

async function emitWithAck(
  event: string,
  payload: Record<string, unknown>
): Promise<Record<string, unknown>> {
  const socket = useSocketStore.getState().socket;
  if (!socket?.connected) {
    throw new CallOperationError(
      "Mất kết nối với máy chủ. Vui lòng thử lại.",
      "SOCKET_DISCONNECTED"
    );
  }

  try {
    const response: unknown = await socket
      .timeout(ACK_TIMEOUT_MS)
      .emitWithAck(event, payload);
    return successfulAck(response);
  } catch (error) {
    if (error instanceof CallOperationError) throw error;
    throw new CallOperationError(
      "Máy chủ phản hồi quá chậm. Vui lòng thử lại.",
      "ACK_TIMEOUT"
    );
  }
}

function stopStream(stream: MediaStream | null): void {
  stream?.getTracks().forEach((track) => track.stop());
}

function clearDisconnectTimer(): void {
  if (disconnectTimer) {
    clearTimeout(disconnectTimer);
    disconnectTimer = null;
  }
}

function clearConnectionSetupTimer(): void {
  if (connectionSetupTimer) {
    clearTimeout(connectionSetupTimer);
    connectionSetupTimer = null;
  }
}

function disposeMediaResources(): void {
  clearDisconnectTimer();
  clearConnectionSetupTimer();

  if (peerConnection) {
    peerConnection.onicecandidate = null;
    peerConnection.ontrack = null;
    peerConnection.onconnectionstatechange = null;
    peerConnection.close();
    peerConnection = null;
  }

  stopStream(localStream);
  stopStream(remoteMediaStream);
  localStream = null;
  remoteMediaStream = null;
  pendingIceCandidates = [];
  signalQueue = Promise.resolve();
}

function resetCall(error: string | null = null): void {
  sessionVersion += 1;
  disposeMediaResources();
  useCallStore.setState({
    status: "idle",
    direction: null,
    callId: null,
    conversationId: null,
    peer: null,
    mediaType: "audio",
    startedAt: null,
    muted: false,
    cameraEnabled: false,
    operationPending: false,
    error,
    localStream: null,
    remoteStream: null,
  });
}

function beginCallSession(): number {
  sessionVersion += 1;
  disposeMediaResources();
  return sessionVersion;
}

function getIceServers(): RTCIceServer[] {
  const stunUrl = import.meta.env.VITE_WEBRTC_STUN_URL?.trim() || DEFAULT_STUN_URL;
  const iceServers: RTCIceServer[] = [{ urls: stunUrl }];

  const turnUrl = import.meta.env.VITE_WEBRTC_TURN_URL?.trim();
  if (turnUrl) {
    const turnServer: RTCIceServer = { urls: turnUrl };
    const username = import.meta.env.VITE_WEBRTC_TURN_USERNAME?.trim();
    const credential = import.meta.env.VITE_WEBRTC_TURN_CREDENTIAL?.trim();

    if (username) turnServer.username = username;
    if (credential) turnServer.credential = credential;
    iceServers.push(turnServer);
  }

  return iceServers;
}

async function requestMedia(mediaType: CallMediaType): Promise<MediaStream> {
  const isVideo = mediaType === "video";
  if (!window.isSecureContext) {
    throw new CallOperationError(
      "Trình duyệt chỉ cho phép gọi trên HTTPS hoặc localhost.",
      "INSECURE_CONTEXT"
    );
  }

  if (!navigator.mediaDevices?.getUserMedia) {
    throw new CallOperationError(
      "Trình duyệt hoặc thiết bị này không hỗ trợ truy cập microphone/camera.",
      "MEDIA_UNSUPPORTED"
    );
  }

  try {
    return await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
      video: isVideo
        ? {
            facingMode: "user",
            width: { ideal: 1280 },
            height: { ideal: 720 },
          }
        : false,
    });
  } catch (error) {
    if (error instanceof DOMException) {
      if (error.name === "NotAllowedError" || error.name === "SecurityError") {
        throw new CallOperationError(
          isVideo
            ? "Bạn cần cấp quyền sử dụng microphone và camera để gọi video."
            : "Bạn cần cấp quyền sử dụng microphone để gọi thoại.",
          "MEDIA_PERMISSION_DENIED"
        );
      }
      if (error.name === "NotFoundError" || error.name === "DevicesNotFoundError") {
        throw new CallOperationError(
          isVideo
            ? "Không tìm thấy microphone hoặc camera trên thiết bị."
            : "Không tìm thấy microphone trên thiết bị.",
          "MEDIA_NOT_FOUND"
        );
      }
      if (error.name === "NotReadableError" || error.name === "TrackStartError") {
        throw new CallOperationError(
          isVideo
            ? "Microphone hoặc camera đang được ứng dụng khác sử dụng."
            : "Microphone đang được ứng dụng khác sử dụng.",
          "MEDIA_NOT_READABLE"
        );
      }
    }

    throw new CallOperationError(
      isVideo
        ? "Không thể mở microphone hoặc camera. Vui lòng kiểm tra quyền truy cập."
        : "Không thể mở microphone. Vui lòng kiểm tra quyền truy cập.",
      "MEDIA_ERROR"
    );
  }
}

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  return "Đã xảy ra lỗi khi thiết lập cuộc gọi.";
}

function endedMessage(reason: string): string | null {
  switch (reason) {
    case "declined":
      return "Người dùng đã từ chối cuộc gọi.";
    case "canceled":
      return "Cuộc gọi đã bị hủy.";
    case "no-answer":
      return "Không có phản hồi từ người nhận.";
    case "answered-elsewhere":
      return "Cuộc gọi đã được trả lời trên thiết bị khác.";
    case "disconnected":
      return "Đầu bên kia đã mất kết nối.";
    case "media-error":
      return "Thiết bị bên kia không thể sử dụng camera/microphone.";
    case "connection-failed":
      return "Không thể duy trì kết nối cuộc gọi.";
    case "busy":
      return "Người nhận đang bận.";
    case "ended":
      return "Cuộc gọi đã kết thúc.";
    default:
      return reason ? "Cuộc gọi đã kết thúc." : null;
  }
}

function sendSignal(callId: string, signal: CallSignal): Promise<void> {
  return emitWithAck("call:signal", { callId, signal }).then(() => undefined);
}

function sendIceCandidate(callId: string, candidate: RTCIceCandidate): void {
  const signal: IceCandidateSignal = {
    type: "ice-candidate",
    candidate: candidate.candidate,
  };

  if (candidate.sdpMid !== null) signal.sdpMid = candidate.sdpMid;
  if (candidate.sdpMLineIndex !== null) {
    signal.sdpMLineIndex = candidate.sdpMLineIndex;
  }

  void sendSignal(callId, signal).catch((error) => {
    console.warn("Không thể gửi ICE candidate:", error);
  });
}

function failCurrentConnection(callId: string, message: string): void {
  const state = useCallStore.getState();
  if (state.callId !== callId || state.status === "idle") return;

  // Emit synchronously before closing media/peer resources so the server can
  // release both users even when the local WebRTC connection is already bad.
  const endRequest = emitWithAck("call:end", {
    callId,
    reason: "connection-failed",
  });
  resetCall(message);
  toast.error(message);
  void endRequest.catch(
    (error) => console.warn("Không thể báo kết thúc cuộc gọi:", error)
  );
}

function startConnectionSetupTimer(callId: string, version: number): void {
  if (connectionSetupTimer) return;
  connectionSetupTimer = setTimeout(() => {
    connectionSetupTimer = null;
    const state = useCallStore.getState();
    if (
      version === sessionVersion &&
      state.callId === callId &&
      state.status !== "active"
    ) {
      failCurrentConnection(callId, "Quá thời gian thiết lập kết nối cuộc gọi.");
    }
  }, CONNECTION_SETUP_TIMEOUT_MS);
}

function ensurePeerConnection(callId: string, version: number): RTCPeerConnection {
  if (peerConnection) return peerConnection;
  if (typeof RTCPeerConnection === "undefined") {
    throw new CallOperationError(
      "Trình duyệt này không hỗ trợ cuộc gọi WebRTC.",
      "WEBRTC_UNSUPPORTED"
    );
  }
  if (!localStream) {
    throw new CallOperationError(
      "Thiết bị media chưa sẵn sàng cho cuộc gọi.",
      "MEDIA_NOT_READY"
    );
  }

  const connection = new RTCPeerConnection({
    iceServers: getIceServers(),
    bundlePolicy: "max-bundle",
  });
  peerConnection = connection;
  remoteMediaStream = new MediaStream();
  startConnectionSetupTimer(callId, version);

  localStream.getTracks().forEach((track) => {
    connection.addTrack(track, localStream as MediaStream);
  });

  connection.onicecandidate = (event) => {
    if (
      event.candidate &&
      version === sessionVersion &&
      useCallStore.getState().callId === callId
    ) {
      sendIceCandidate(callId, event.candidate);
    }
  };

  connection.ontrack = (event) => {
    if (version !== sessionVersion || useCallStore.getState().callId !== callId) {
      return;
    }

    const stream = remoteMediaStream;
    if (!stream) return;

    if (!stream.getTracks().some((track) => track.id === event.track.id)) {
      stream.addTrack(event.track);
    }
    remoteMediaStream = new MediaStream(stream.getTracks());
    useCallStore.setState({ remoteStream: remoteMediaStream });
  };

  connection.onconnectionstatechange = () => {
    if (version !== sessionVersion || useCallStore.getState().callId !== callId) {
      return;
    }

    switch (connection.connectionState) {
      case "connected":
        clearDisconnectTimer();
        clearConnectionSetupTimer();
        useCallStore.setState((state) => ({
          status: "active",
          startedAt: state.startedAt ?? Date.now(),
        }));
        break;
      case "connecting":
        useCallStore.setState((state) =>
          state.status === "active" ? state : { status: "connecting" }
        );
        break;
      case "disconnected":
        clearDisconnectTimer();
        disconnectTimer = setTimeout(() => {
          if (
            peerConnection?.connectionState === "disconnected" &&
            useCallStore.getState().callId === callId
          ) {
            failCurrentConnection(callId, "Kết nối cuộc gọi đã bị gián đoạn.");
          }
        }, DISCONNECT_GRACE_MS);
        break;
      case "failed":
        failCurrentConnection(callId, "Không thể thiết lập kết nối cuộc gọi.");
        break;
      case "closed":
      case "new":
        break;
    }
  };

  return connection;
}

async function flushPendingIce(connection: RTCPeerConnection): Promise<void> {
  const candidates = pendingIceCandidates;
  pendingIceCandidates = [];
  for (const candidate of candidates) {
    await connection.addIceCandidate(candidate);
  }
}

async function processSignal(payload: CallSignalPayload): Promise<void> {
  const state = useCallStore.getState();
  const version = sessionVersion;
  if (
    state.callId !== payload.callId ||
    state.status === "idle" ||
    !localStream
  ) {
    return;
  }

  const connection = ensurePeerConnection(payload.callId, version);
  const { signal } = payload;

  if (signal.type === "ice-candidate") {
    const candidate: RTCIceCandidateInit = {
      candidate: signal.candidate,
      sdpMid: signal.sdpMid,
      sdpMLineIndex: signal.sdpMLineIndex,
    };

    if (!connection.remoteDescription) {
      pendingIceCandidates.push(candidate);
      return;
    }

    await connection.addIceCandidate(candidate);
    return;
  }

  await connection.setRemoteDescription({ type: signal.type, sdp: signal.sdp });
  await flushPendingIce(connection);

  if (signal.type === "offer") {
    const answer = await connection.createAnswer();
    await connection.setLocalDescription(answer);
    if (version !== sessionVersion || !answer.sdp) return;
    await sendSignal(payload.callId, { type: "answer", sdp: answer.sdp });
  }
}

function enqueueSignal(payload: CallSignalPayload): void {
  signalQueue = signalQueue
    .then(() => processSignal(payload))
    .catch((error) => {
      console.error("Lỗi xử lý WebRTC signal:", error);
      failCurrentConnection(payload.callId, errorMessage(error));
    });
}

async function sendTermination(
  event: "call:reject" | "call:cancel" | "call:end",
  callId: string,
  reason?: string
): Promise<boolean> {
  try {
    const payload: Record<string, unknown> = { callId };
    if (reason) payload.reason = reason;
    await emitWithAck(event, payload);
    return true;
  } catch (error) {
    console.warn(`Không thể gửi ${event}:`, error);
    return false;
  }
}

async function cancelOrEndCall(callId: string): Promise<void> {
  const cancelled = await sendTermination("call:cancel", callId);
  if (!cancelled) {
    // The callee may have accepted while call:cancel was in flight. In that
    // narrow race the server has already moved the call to active.
    await sendTermination("call:end", callId, "ended");
  }
}

export const useCallStore = create<CallState>((set, get) => ({
  status: "idle",
  direction: null,
  callId: null,
  conversationId: null,
  peer: null,
  mediaType: "audio",
  startedAt: null,
  muted: false,
  cameraEnabled: false,
  operationPending: false,
  error: null,
  localStream: null,
  remoteStream: null,

  startCall: async (
    peer: CallPeer,
    conversationId: string,
    mediaType: CallMediaType
  ) => {
    if (get().status !== "idle") return;

    const socket = useSocketStore.getState().socket;
    if (!socket?.connected) {
      const message = "Chưa kết nối với máy chủ cuộc gọi.";
      set({ error: message });
      toast.error(message);
      return;
    }

    const version = beginCallSession();
    set({
      status: "outgoing",
      direction: "outgoing",
      callId: null,
      conversationId,
      peer,
      mediaType,
      startedAt: null,
      muted: false,
      cameraEnabled: mediaType === "video",
      operationPending: true,
      error: null,
      localStream: null,
      remoteStream: null,
    });

    try {
      const stream = await requestMedia(mediaType);
      if (version !== sessionVersion) {
        stopStream(stream);
        return;
      }
      localStream = stream;
      set({ localStream: stream });

      const ack = await emitWithAck("call:start", {
        calleeId: peer.id,
        conversationId,
        mediaType,
      });
      const callId = readString(ack.callId);
      if (
        !callId ||
        !readString(ack.createdAt) ||
        typeof ack.timeoutMs !== "number" ||
        !Number.isFinite(ack.timeoutMs) ||
        ack.timeoutMs <= 0 ||
        readMediaType(ack.mediaType) !== mediaType
      ) {
        throw new CallOperationError(
          "Máy chủ không trả về dữ liệu cuộc gọi hợp lệ.",
          "INVALID_START_ACK"
        );
      }

      if (version !== sessionVersion) {
        void cancelOrEndCall(callId);
        return;
      }

      set({ callId, operationPending: false });
    } catch (error) {
      if (version !== sessionVersion) return;
      const message = errorMessage(error);
      resetCall(message);
      toast.error(message);
    }
  },

  acceptCall: async () => {
    const { status, callId, mediaType } = get();
    if (status !== "incoming" || !callId || get().operationPending) return;

    const version = sessionVersion;
    set({ operationPending: true, error: null });

    try {
      const stream = await requestMedia(mediaType);
      if (version !== sessionVersion) {
        stopStream(stream);
        return;
      }
      localStream = stream;
      set({
        localStream: stream,
        cameraEnabled: mediaType === "video",
      });

      await emitWithAck("call:accept", { callId });
      if (version !== sessionVersion) return;
      if (get().status !== "active") {
        startConnectionSetupTimer(callId, version);
      }
      set((state) => ({
        status: state.status === "active" ? "active" : "connecting",
        operationPending: false,
      }));
    } catch (error) {
      if (version !== sessionVersion) return;
      const message = errorMessage(error);
      resetCall(message);
      toast.error(message);
      void sendTermination("call:reject", callId, "media-error");
    }
  },

  rejectCall: async () => {
    const { status, callId } = get();
    if (status !== "incoming" || !callId) return;
    resetCall();
    await sendTermination("call:reject", callId);
  },

  cancelCall: async () => {
    const { status, callId } = get();
    if (status !== "outgoing") return;
    resetCall();
    if (callId) await cancelOrEndCall(callId);
  },

  endCall: async () => {
    const { status, callId } = get();
    if (status === "idle" || !callId) return;
    resetCall();
    await sendTermination("call:end", callId, "ended");
  },

  toggleMute: () => {
    if (!localStream) return;
    const nextMuted = !get().muted;
    localStream.getAudioTracks().forEach((track) => {
      track.enabled = !nextMuted;
    });
    set({ muted: nextMuted });
  },

  toggleCamera: () => {
    if (!localStream || get().mediaType !== "video") return;
    const videoTracks = localStream.getVideoTracks();
    if (videoTracks.length === 0) return;
    const nextEnabled = !get().cameraEnabled;
    videoTracks.forEach((track) => {
      track.enabled = nextEnabled;
    });
    set({ cameraEnabled: nextEnabled });
  },

  handleIncoming: (rawPayload: unknown) => {
    const payload = parseIncomingCall(rawPayload);
    if (!payload) {
      console.warn("Bỏ qua call:incoming không hợp lệ", rawPayload);
      return;
    }

    const current = get();
    if (current.status !== "idle") {
      if (current.callId !== payload.callId) {
        void sendTermination("call:reject", payload.callId, "busy");
      }
      return;
    }

    beginCallSession();
    set({
      status: "incoming",
      direction: "incoming",
      callId: payload.callId,
      conversationId: payload.conversationId,
      peer: payload.caller,
      mediaType: payload.mediaType,
      startedAt: null,
      muted: false,
      cameraEnabled: false,
      operationPending: false,
      error: null,
      localStream: null,
      remoteStream: null,
    });
  },

  handleAccepted: async (rawPayload: unknown) => {
    const payload = parseAcceptedCall(rawPayload);
    if (!payload) {
      console.warn("Bỏ qua call:accepted không hợp lệ", rawPayload);
      return;
    }

    const current = get();
    if (
      current.direction !== "outgoing" ||
      current.callId !== payload.callId ||
      current.status !== "outgoing" ||
      current.mediaType !== payload.mediaType ||
      !localStream
    ) {
      return;
    }

    const version = sessionVersion;
    startConnectionSetupTimer(payload.callId, version);
    set({ status: "connecting", operationPending: false });

    try {
      const connection = ensurePeerConnection(payload.callId, version);
      const offer = await connection.createOffer();
      await connection.setLocalDescription(offer);
      if (version !== sessionVersion || !offer.sdp) return;
      await sendSignal(payload.callId, { type: "offer", sdp: offer.sdp });
    } catch (error) {
      console.error("Không thể tạo WebRTC offer:", error);
      failCurrentConnection(payload.callId, errorMessage(error));
    }
  },

  handleEnded: (rawPayload: unknown) => {
    const payload = parseEndedCall(rawPayload);
    if (!payload) {
      console.warn("Bỏ qua call:ended không hợp lệ", rawPayload);
      return;
    }

    if (get().callId !== payload.callId) return;
    const message = endedMessage(payload.reason);
    resetCall();
    if (message) toast.info(message);
  },

  handleSignal: (rawPayload: unknown) => {
    const payload = parseCallSignal(rawPayload);
    if (!payload) {
      console.warn("Bỏ qua call:signal không hợp lệ", rawPayload);
      return;
    }

    if (get().callId !== payload.callId) return;
    enqueueSignal(payload);
  },

  handleSocketDisconnect: () => {
    const hadCall = get().status !== "idle";
    resetCall(hadCall ? "Mất kết nối với máy chủ cuộc gọi." : null);
    if (hadCall) toast.error("Cuộc gọi kết thúc vì mất kết nối máy chủ.");
  },
}));
