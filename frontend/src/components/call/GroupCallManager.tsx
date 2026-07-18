import { useEffect, useRef, useState } from "react";
import { Camera, CameraOff, MessageSquare, Mic, MicOff, Phone, PhoneOff, Users, Video } from "lucide-react";
import { useSocketStore } from "@/stores/useSocketStore";
import { useGroupCallStore, type GroupCallParticipant } from "@/stores/useGroupCallStore";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "../ui/dialog";
import UserAvatar from "../chat/UserAvatar";
import { useAuthStore } from "@/stores/useAuthStore";
import { useChatStore } from "@/stores/useChatStore";
import InCallChatPanel from "./InCallChatPanel";

function MediaTile({ stream, participant, muted = false }: { stream: MediaStream | null; participant: GroupCallParticipant; muted?: boolean }) {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    const videoElement = ref.current;
    if (!videoElement) return;
    videoElement.srcObject = stream;
    if (stream) void videoElement.play().catch(() => undefined);
    return () => {
      videoElement.srcObject = null;
    };
  }, [stream]);
  const video = stream?.getVideoTracks().some((track) => track.enabled && track.readyState === "live");
  return (
    <div className="relative flex min-h-40 items-center justify-center overflow-hidden rounded-2xl bg-slate-900">
      <video ref={ref} autoPlay playsInline muted={muted} className={video ? "h-full w-full object-cover" : "hidden"} />
      {!video && <UserAvatar type="profile" name={participant.displayName} avatarUrl={participant.avatarUrl ?? undefined} />}
      <span className="absolute bottom-2 left-2 rounded-full bg-black/55 px-2 py-1 text-xs text-white">{participant.displayName}</span>
    </div>
  );
}

export default function GroupCallManager() {
  const socket = useSocketStore((state) => state.socket);
  const currentUserId = useAuthStore((state) => state.user?._id);
  const state = useGroupCallStore();
  const [chatOpen, setChatOpen] = useState(false);
  const conversation = useChatStore((chat) =>
    chat.conversations.find((item) => item._id === state.conversationId)
  );
  useEffect(() => {
    if (!socket) return;
    const incoming = (p: unknown) => useGroupCallStore.getState().handleIncoming(p);
    const active = (p: unknown) => useGroupCallStore.getState().handleActive(p);
    const joined = (p: unknown) => useGroupCallStore.getState().handleParticipantJoined(p);
    const left = (p: unknown) => useGroupCallStore.getState().handleParticipantLeft(p);
    const signal = (p: unknown) => useGroupCallStore.getState().handleSignal(p);
    const ended = (p: unknown) => useGroupCallStore.getState().handleEnded(p);
    socket.on("group-call:incoming", incoming);
    socket.on("group-call:active", active);
    socket.on("group-call:participant-joined", joined);
    socket.on("group-call:participant-left", left);
    socket.on("group-call:signal", signal);
    socket.on("group-call:ended", ended);
    socket.on("group-call:dismissed", ended);
    return () => {
      socket.off("group-call:incoming", incoming); socket.off("group-call:participant-joined", joined);
      socket.off("group-call:active", active);
      socket.off("group-call:participant-left", left); socket.off("group-call:signal", signal);
      socket.off("group-call:ended", ended); socket.off("group-call:dismissed", ended);
    };
  }, [socket]);

  useEffect(() => {
    if (state.status === "idle") setChatOpen(false);
  }, [state.status]);

  if (state.status === "idle") return null;
  if (state.status === "incoming") {
    return (
      <Dialog open>
        <DialogContent showCloseButton={false} className="sm:max-w-sm">
          <DialogHeader><DialogTitle>Cuộc gọi nhóm đến</DialogTitle><DialogDescription>{state.conversationName} · {state.mediaType === "video" ? "Gọi video" : "Gọi thoại"}</DialogDescription></DialogHeader>
          <div className="flex flex-col items-center gap-3 py-5">
            <UserAvatar type="profile" name={state.caller?.displayName ?? state.conversationName} avatarUrl={state.caller?.avatarUrl ?? undefined} />
            <p className="font-semibold">{state.caller?.displayName} đang mời bạn</p>
          </div>
          <div className="flex justify-center gap-12">
            <Button size="icon-lg" className="size-14 rounded-full bg-destructive" onClick={state.dismiss}><PhoneOff /></Button>
            <Button size="icon-lg" className="size-14 rounded-full bg-emerald-500" onClick={() => void state.join()}>{state.mediaType === "video" ? <Video /> : <Phone />}</Button>
          </div>
        </DialogContent>
      </Dialog>
    );
  }

  const self = state.participants.find((p) => p.userId === currentUserId);
  return (
    <Dialog open>
      <DialogContent showCloseButton={false} className="flex h-[min(90vh,800px)] max-w-6xl flex-col overflow-hidden bg-slate-950 text-white sm:max-w-6xl">
        <DialogHeader><DialogTitle className="flex items-center gap-2"><Users /> {state.conversationName}</DialogTitle><DialogDescription>{state.status === "joining" ? "Đang tham gia..." : `${state.participants.length} người trong cuộc gọi`}</DialogDescription></DialogHeader>
        <div className="flex min-h-0 flex-1 gap-3">
          <div className={`${chatOpen ? "hidden sm:grid" : "grid"} min-w-0 flex-1 grid-cols-1 gap-3 overflow-y-auto sm:grid-cols-2 lg:grid-cols-3`}>
            {self && <MediaTile participant={{ ...self, displayName: `${self.displayName} (Bạn)` }} stream={state.localStream} muted />}
            {state.participants.filter((p) => p !== self).map((p) => <MediaTile key={p.socketId} participant={p} stream={state.remoteStreams[p.userId] ?? null} />)}
          </div>
          {chatOpen && state.conversationId && (
            <InCallChatPanel
              conversationId={state.conversationId}
              currentUserId={currentUserId}
              mode="group"
              senderName={(userId) =>
                conversation?.participants.find((member) => member._id === userId)
                  ?.displayName
              }
              onClose={() => setChatOpen(false)}
              className="w-full shrink-0 sm:w-80"
            />
          )}
        </div>
        <div className="flex justify-center gap-4 pt-3">
          <Button size="icon-lg" variant="secondary" className="size-14 rounded-full" onClick={state.toggleMute}>{state.muted ? <MicOff /> : <Mic />}</Button>
          {state.mediaType === "video" && <Button size="icon-lg" variant="secondary" className="size-14 rounded-full" onClick={state.toggleCamera}>{state.cameraEnabled ? <Camera /> : <CameraOff />}</Button>}
          <Button size="icon-lg" variant={chatOpen ? "default" : "secondary"} className="size-14 rounded-full" title="Nhắn tin trong cuộc gọi" onClick={() => setChatOpen((value) => !value)}><MessageSquare /></Button>
          <Button size="icon-lg" className="size-14 rounded-full bg-destructive" onClick={() => void state.leave()}><PhoneOff /></Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
