import { create } from "zustand";
import { toast } from "sonner";
import { useSocketStore } from "./useSocketStore";
import { useCallStore } from "./useCallStore";
import type { CallMediaType, CallSignal } from "@/types/call";

export interface GroupCallParticipant {
  userId: string;
  socketId: string;
  displayName: string;
  avatarUrl?: string | null;
  isCaller?: boolean;
}

export interface ActiveGroupCallRoom {
  callId: string;
  conversationId: string;
  conversationName: string;
  mediaType: CallMediaType;
  participantCount: number;
}

type GroupCallStatus = "idle" | "incoming" | "joining" | "active";
interface GroupCallState {
  status: GroupCallStatus;
  callId: string | null;
  conversationId: string | null;
  conversationName: string;
  mediaType: CallMediaType;
  caller: GroupCallParticipant | null;
  participants: GroupCallParticipant[];
  localStream: MediaStream | null;
  remoteStreams: Record<string, MediaStream>;
  muted: boolean;
  cameraEnabled: boolean;
  startedAt: number | null;
  activeRoom: ActiveGroupCallRoom | null;
  start: (conversationId: string, name: string, mediaType: CallMediaType) => Promise<void>;
  checkActive: (conversationId: string) => Promise<void>;
  join: () => Promise<void>;
  dismiss: () => void;
  leave: () => Promise<void>;
  toggleMute: () => void;
  toggleCamera: () => void;
  handleIncoming: (payload: unknown) => void;
  handleActive: (payload: unknown) => void;
  handleParticipantJoined: (payload: unknown) => void;
  handleParticipantLeft: (payload: unknown) => void;
  handleSignal: (payload: unknown) => void;
  handleEnded: (payload: unknown) => void;
}

const peers = new Map<string, RTCPeerConnection>();
const pendingIce = new Map<string, RTCIceCandidateInit[]>();
let local: MediaStream | null = null;

const record = (value: unknown): Record<string, any> =>
  typeof value === "object" && value !== null ? (value as Record<string, any>) : {};

function participant(value: unknown): GroupCallParticipant | null {
  const item = record(value);
  if (!item.userId || !item.socketId) return null;
  return {
    userId: String(item.userId),
    socketId: String(item.socketId),
    displayName: String(item.displayName || "Thành viên"),
    avatarUrl: typeof item.avatarUrl === "string" ? item.avatarUrl : null,
    isCaller: item.isCaller === true,
  };
}

async function ack(event: string, payload: Record<string, unknown>) {
  const socket = useSocketStore.getState().socket;
  if (!socket?.connected) throw new Error("Mất kết nối máy chủ cuộc gọi.");
  const response = record(await socket.timeout(8000).emitWithAck(event, payload));
  if (response.ok !== true) throw new Error(record(response.error).message || "Yêu cầu cuộc gọi thất bại.");
  return response;
}

async function media(type: CallMediaType) {
  return navigator.mediaDevices.getUserMedia({
    audio: { echoCancellation: true, noiseSuppression: true },
    video: type === "video" ? { facingMode: "user", width: { ideal: 1280 }, height: { ideal: 720 } } : false,
  });
}

function cleanup() {
  peers.forEach((pc) => pc.close());
  peers.clear();
  pendingIce.clear();
  local?.getTracks().forEach((track) => track.stop());
  local = null;
}

function reset(activeRoom: ActiveGroupCallRoom | null = null) {
  cleanup();
  useGroupCallStore.setState({
    status: "idle", callId: null, conversationId: null, conversationName: "",
    caller: null, participants: [], localStream: null, remoteStreams: {},
    muted: false, cameraEnabled: false, startedAt: null, activeRoom,
  });
}

function roomFromPayload(value: unknown): ActiveGroupCallRoom | null {
  const item = record(value);
  const conversation = record(item.conversation);
  const callId = String(item.callId || "");
  const conversationId = String(item.conversationId || conversation.id || "");
  if (!callId || !conversationId) return null;
  return {
    callId,
    conversationId,
    conversationName: String(conversation.name || item.conversationName || "Nhóm chat"),
    mediaType: item.mediaType === "video" ? "video" : "audio",
    participantCount: Number(item.participantCount || 0),
  };
}

async function relay(targetSocketId: string, signal: CallSignal) {
  const callId = useGroupCallStore.getState().callId;
  if (callId) await ack("group-call:signal", { callId, targetSocketId, signal });
}

function makePeer(peer: GroupCallParticipant): RTCPeerConnection {
  const existing = peers.get(peer.socketId);
  if (existing) return existing;
  const pc = new RTCPeerConnection({ iceServers: [{ urls: import.meta.env.VITE_WEBRTC_STUN_URL?.trim() || "stun:stun.l.google.com:19302" }] });
  peers.set(peer.socketId, pc);
  local?.getTracks().forEach((track) => pc.addTrack(track, local!));
  pc.onicecandidate = (event) => {
    if (!event.candidate) return;
    const candidate = event.candidate.toJSON();
    void relay(peer.socketId, { type: "ice-candidate", candidate: candidate.candidate!, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex });
  };
  pc.ontrack = (event) => {
    const stream = event.streams[0] ?? new MediaStream([event.track]);
    useGroupCallStore.setState((state) => ({ remoteStreams: { ...state.remoteStreams, [peer.userId]: stream } }));
  };
  return pc;
}

async function offer(peer: GroupCallParticipant) {
  const pc = makePeer(peer);
  const description = await pc.createOffer();
  await pc.setLocalDescription(description);
  if (description.sdp) await relay(peer.socketId, { type: "offer", sdp: description.sdp });
}

async function processSignal(raw: unknown) {
  const payload = record(raw);
  if (payload.callId !== useGroupCallStore.getState().callId) return;
  const fromSocketId = String(payload.fromSocketId || "");
  const fromUserId = String(payload.fromUserId || "");
  if (!fromSocketId || !fromUserId) return;
  const known = useGroupCallStore.getState().participants.find((p) => p.socketId === fromSocketId) ?? {
    userId: fromUserId, socketId: fromSocketId, displayName: "Thành viên",
  };
  const pc = makePeer(known);
  const signal = record(payload.signal);
  if (signal.type === "ice-candidate") {
    const candidate = { candidate: signal.candidate, sdpMid: signal.sdpMid, sdpMLineIndex: signal.sdpMLineIndex };
    if (!pc.remoteDescription) pendingIce.set(fromSocketId, [...(pendingIce.get(fromSocketId) ?? []), candidate]);
    else await pc.addIceCandidate(candidate);
    return;
  }
  if (signal.type !== "offer" && signal.type !== "answer") return;
  await pc.setRemoteDescription({ type: signal.type, sdp: signal.sdp });
  for (const candidate of pendingIce.get(fromSocketId) ?? []) await pc.addIceCandidate(candidate);
  pendingIce.delete(fromSocketId);
  if (signal.type === "offer") {
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    if (answer.sdp) await relay(fromSocketId, { type: "answer", sdp: answer.sdp });
  }
}

export const useGroupCallStore = create<GroupCallState>((set, get) => ({
  status: "idle", callId: null, conversationId: null, conversationName: "", mediaType: "audio",
  caller: null, participants: [], localStream: null, remoteStreams: {}, muted: false,
  cameraEnabled: false, startedAt: null,
  activeRoom: null,
  start: async (conversationId, name, mediaType) => {
    if (get().status !== "idle" || useCallStore.getState().status !== "idle") return;
    try {
      const activeResponse = await ack("group-call:get-active", { conversationId });
      const existingRoom = activeResponse.active === true
        ? roomFromPayload(activeResponse.call)
        : null;
      if (existingRoom) {
        set({
          status: "incoming",
          callId: existingRoom.callId,
          conversationId,
          conversationName: existingRoom.conversationName || name,
          mediaType: existingRoom.mediaType,
          activeRoom: existingRoom,
        });
        await get().join();
        return;
      }

      set({ status: "joining", conversationId, conversationName: name, mediaType });
      local = await media(mediaType);
      const response = await ack("group-call:start", { conversationId, mediaType });
      const list = (Array.isArray(response.participants) ? response.participants : []).map(participant).filter(Boolean) as GroupCallParticipant[];
      const room = roomFromPayload({
        ...response,
        conversationName: name,
        participantCount: list.length,
      });
      set({ status: "active", callId: String(response.callId), participants: list, localStream: local, cameraEnabled: mediaType === "video", startedAt: Date.now(), activeRoom: room });
    } catch (error) { reset(); toast.error(error instanceof Error ? error.message : "Không thể gọi nhóm."); }
  },
  checkActive: async (conversationId) => {
    try {
      const response = await ack("group-call:get-active", { conversationId });
      const room = response.active === true ? roomFromPayload(response.call) : null;
      set((state) => ({
        activeRoom: room ?? (state.activeRoom?.conversationId === conversationId ? null : state.activeRoom),
      }));
    } catch {
      // Mất kết nối tạm thời không được làm gián đoạn giao diện chat.
    }
  },
  join: async () => {
    const id = get().callId;
    if (!id || get().status !== "incoming" || useCallStore.getState().status !== "idle") return;
    set({ status: "joining" });
    try {
      local = await media(get().mediaType);
      const response = await ack("group-call:join", { callId: id });
      const list = (Array.isArray(response.participants) ? response.participants : []).map(participant).filter(Boolean) as GroupCallParticipant[];
      const room = roomFromPayload(response);
      set({ status: "active", participants: list, localStream: local, cameraEnabled: get().mediaType === "video", startedAt: Date.now(), activeRoom: room ?? get().activeRoom });
      const socketId = useSocketStore.getState().socket?.id;
      for (const peer of list) if (peer.socketId !== socketId) await offer(peer);
    } catch (error) { reset(); toast.error(error instanceof Error ? error.message : "Không thể tham gia cuộc gọi nhóm."); }
  },
  dismiss: () => {
    const state = get();
    reset(state.callId && state.conversationId ? {
      callId: state.callId,
      conversationId: state.conversationId,
      conversationName: state.conversationName,
      mediaType: state.mediaType,
      participantCount: state.participants.length,
    } : state.activeRoom);
  },
  leave: async () => {
    const state = get();
    const id = state.callId;
    const room = id && state.conversationId ? {
      callId: id,
      conversationId: state.conversationId,
      conversationName: state.conversationName,
      mediaType: state.mediaType,
      participantCount: Math.max(0, state.participants.length - 1),
    } : state.activeRoom;
    reset(room);
    if (id) { try { await ack("group-call:leave", { callId: id, reason: "left" }); } catch { /* local cleanup */ } }
  },
  toggleMute: () => { const value = !get().muted; local?.getAudioTracks().forEach((track) => { track.enabled = !value; }); set({ muted: value }); },
  toggleCamera: () => { const value = !get().cameraEnabled; local?.getVideoTracks().forEach((track) => { track.enabled = value; }); set({ cameraEnabled: value }); },
  handleIncoming: (raw) => {
    const payload = record(raw);
    if (get().status !== "idle" || useCallStore.getState().status !== "idle") return;
    const callerRaw = record(payload.caller);
    const room = roomFromPayload(payload);
    set({ status: "incoming", callId: String(payload.callId), conversationId: String(payload.conversationId), conversationName: String(record(payload.conversation).name || "Nhóm chat"), mediaType: payload.mediaType === "video" ? "video" : "audio", caller: { userId: String(callerRaw.id), socketId: "", displayName: String(callerRaw.displayName || "Thành viên"), avatarUrl: callerRaw.avatarUrl }, participants: [], activeRoom: room });
  },
  handleActive: (raw) => {
    const payload = record(raw);
    const current = get().activeRoom;
    const room = roomFromPayload({ ...payload, conversationName: current?.conversationName });
    if (room) set({ activeRoom: room });
  },
  handleParticipantJoined: (raw) => {
    const payload = record(raw);
    const currentRoom = get().activeRoom;
    if (currentRoom && currentRoom.callId === payload.callId) {
      set({
        activeRoom: {
          ...currentRoom,
          participantCount:
            typeof payload.participantCount === "number"
              ? payload.participantCount
              : currentRoom.participantCount + 1,
        },
      });
    }
    if (payload.callId !== get().callId) return;
    const item = participant(payload.participant);
    if (item) {
      set((state) => ({
        participants: [
          ...state.participants.filter((entry) => entry.userId !== item.userId),
          item,
        ],
      }));
    }
  },
  handleParticipantLeft: (raw) => {
    const payload = record(raw);
    const currentRoom = get().activeRoom;
    if (currentRoom && currentRoom.callId === payload.callId) {
      set({
        activeRoom: {
          ...currentRoom,
          participantCount:
            typeof payload.participantCount === "number"
              ? payload.participantCount
              : Math.max(0, currentRoom.participantCount - 1),
        },
      });
    }
    if (payload.callId !== get().callId) return;
    const departed = record(payload.participant);
    const socketId = String(departed.socketId || payload.socketId || "");
    const userId = String(departed.userId || payload.userId || "");
    peers.get(socketId)?.close();
    peers.delete(socketId);
    set((state) => {
      const streams = { ...state.remoteStreams };
      delete streams[userId];
      return {
        participants: state.participants.filter((entry) => entry.userId !== userId),
        remoteStreams: streams,
      };
    });
  },
  handleSignal: (raw) => { void processSignal(raw).catch(() => toast.error("Không thể kết nối với một thành viên.")); },
  handleEnded: (raw) => { const payload = record(raw); const isCurrent = payload.callId === get().callId; if (isCurrent || payload.callId === get().activeRoom?.callId) { reset(); if (isCurrent) toast.info("Cuộc gọi nhóm đã kết thúc."); } },
}));
