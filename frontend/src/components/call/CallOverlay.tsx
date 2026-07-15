import { useEffect, useRef, useState } from "react";
import {
  Camera,
  CameraOff,
  Mic,
  MicOff,
  MessageSquare,
  Phone,
  PhoneOff,
  Volume2,
} from "lucide-react";

import { useCallStore } from "@/stores/useCallStore";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import UserAvatar from "@/components/chat/UserAvatar";
import { cn } from "@/lib/utils";
import { useAuthStore } from "@/stores/useAuthStore";
import InCallChatPanel from "./InCallChatPanel";

interface CallOverlayProps {
  audioPlaybackBlocked: boolean;
  onEnableAudio: () => void;
}

interface StreamVideoProps {
  stream: MediaStream | null;
  muted?: boolean;
  mirror?: boolean;
  className?: string;
  label: string;
}

function StreamVideo({
  stream,
  muted = false,
  mirror = false,
  className,
  label,
}: StreamVideoProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [playbackBlocked, setPlaybackBlocked] = useState(false);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    video.srcObject = stream;
    if (!stream) {
      video.pause();
      setPlaybackBlocked(false);
      return;
    }

    let cancelled = false;
    void video
      .play()
      .then(() => {
        if (!cancelled) setPlaybackBlocked(false);
      })
      .catch((error: unknown) => {
        if (
          !cancelled &&
          error instanceof DOMException &&
          error.name === "NotAllowedError"
        ) {
          setPlaybackBlocked(true);
        }
      });

    return () => {
      cancelled = true;
      video.pause();
      if (video.srcObject === stream) video.srcObject = null;
    };
  }, [stream]);

  return (
    <div className={cn("relative h-full w-full overflow-hidden", className)}>
      <video
        ref={videoRef}
        autoPlay
        playsInline
        muted={muted}
        aria-label={label}
        className={cn(
          "h-full w-full object-cover",
          mirror && "-scale-x-100"
        )}
      />
      {playbackBlocked && (
        <Button
          type="button"
          variant="secondary"
          className="absolute bottom-24 left-1/2 z-30 -translate-x-1/2 shadow-lg"
          onClick={() => {
            const video = videoRef.current;
            if (!video) return;
            void video
              .play()
              .then(() => setPlaybackBlocked(false))
              .catch(() => setPlaybackBlocked(true));
          }}
        >
          <Volume2 />
          Bật âm thanh
        </Button>
      )}
    </div>
  );
}

function formatDuration(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes.toString().padStart(2, "0")}:${seconds
    .toString()
    .padStart(2, "0")}`;
}

function useCallDuration(startedAt: number | null): string {
  const [elapsedSeconds, setElapsedSeconds] = useState(0);

  useEffect(() => {
    if (!startedAt) {
      setElapsedSeconds(0);
      return;
    }

    const updateDuration = () => {
      setElapsedSeconds(Math.max(0, Math.floor((Date.now() - startedAt) / 1000)));
    };

    updateDuration();
    const timer = window.setInterval(updateDuration, 1_000);
    return () => window.clearInterval(timer);
  }, [startedAt]);

  return formatDuration(elapsedSeconds);
}

const CallOverlay = ({
  audioPlaybackBlocked,
  onEnableAudio,
}: CallOverlayProps) => {
  const status = useCallStore((state) => state.status);
  const direction = useCallStore((state) => state.direction);
  const peer = useCallStore((state) => state.peer);
  const conversationId = useCallStore((state) => state.conversationId);
  const mediaType = useCallStore((state) => state.mediaType);
  const startedAt = useCallStore((state) => state.startedAt);
  const muted = useCallStore((state) => state.muted);
  const cameraEnabled = useCallStore((state) => state.cameraEnabled);
  const operationPending = useCallStore((state) => state.operationPending);
  const localStream = useCallStore((state) => state.localStream);
  const remoteStream = useCallStore((state) => state.remoteStream);
  const acceptCall = useCallStore((state) => state.acceptCall);
  const rejectCall = useCallStore((state) => state.rejectCall);
  const cancelCall = useCallStore((state) => state.cancelCall);
  const endCall = useCallStore((state) => state.endCall);
  const toggleMute = useCallStore((state) => state.toggleMute);
  const toggleCamera = useCallStore((state) => state.toggleCamera);
  const currentUserId = useAuthStore((state) => state.user?._id);
  const [chatOpen, setChatOpen] = useState(false);
  const duration = useCallDuration(status === "active" ? startedAt : null);

  useEffect(() => {
    if (status === "idle") setChatOpen(false);
  }, [status]);

  if (status === "idle" || !peer) return null;

  const isVideo = mediaType === "video";
  const hasRemoteVideo =
    remoteStream?.getVideoTracks().some((track) => track.readyState === "live") ??
    false;

  let statusText = "Đang kết nối...";
  if (status === "incoming") {
    statusText = operationPending
      ? isVideo
        ? "Đang mở camera và microphone..."
        : "Đang mở microphone..."
      : isVideo
        ? "Cuộc gọi video đến"
        : "Cuộc gọi thoại đến";
  } else if (status === "outgoing") {
    statusText = operationPending
      ? isVideo
        ? "Đang chuẩn bị camera và microphone..."
        : "Đang chuẩn bị microphone..."
      : "Đang đổ chuông...";
  } else if (status === "active") {
    statusText = duration;
  }

  const hangUp = () => {
    if (status === "outgoing") {
      void cancelCall();
      return;
    }
    void endCall();
  };

  const incomingActions = (
    <>
      <div className="flex flex-col items-center gap-2">
        <Button
          type="button"
          size="icon-lg"
          className="size-14 rounded-full bg-destructive text-white hover:bg-destructive/90"
          disabled={operationPending}
          aria-label="Từ chối cuộc gọi"
          title="Từ chối"
          onClick={() => void rejectCall()}
        >
          <PhoneOff className="size-6" />
        </Button>
        <span className="text-xs opacity-80">Từ chối</span>
      </div>

      <div className="flex flex-col items-center gap-2">
        <Button
          type="button"
          size="icon-lg"
          className="size-14 rounded-full bg-emerald-500 text-white hover:bg-emerald-600"
          disabled={operationPending}
          aria-label="Nhận cuộc gọi"
          title="Nghe máy"
          onClick={() => void acceptCall()}
        >
          {isVideo ? <Camera className="size-6" /> : <Phone className="size-6" />}
        </Button>
        <span className="text-xs opacity-80">Nghe máy</span>
      </div>
    </>
  );

  const ongoingActions = (
    <>
      {localStream && (
        <div className="flex flex-col items-center gap-2">
          <Button
            type="button"
            size="icon-lg"
            variant={muted ? "secondary" : "outline"}
            className={cn("size-14 rounded-full", isVideo && "border-white/40 bg-black/35 text-white hover:bg-white/20")}
            aria-label={muted ? "Bật microphone" : "Tắt microphone"}
            title={muted ? "Bật microphone" : "Tắt microphone"}
            onClick={toggleMute}
          >
            {muted ? <MicOff className="size-6" /> : <Mic className="size-6" />}
          </Button>
          <span className="text-xs opacity-80">{muted ? "Bật mic" : "Tắt mic"}</span>
        </div>
      )}

      {isVideo && localStream && (
        <div className="flex flex-col items-center gap-2">
          <Button
            type="button"
            size="icon-lg"
            className="size-14 rounded-full border border-white/40 bg-black/35 text-white hover:bg-white/20"
            aria-label={cameraEnabled ? "Tắt camera" : "Bật camera"}
            title={cameraEnabled ? "Tắt camera" : "Bật camera"}
            onClick={toggleCamera}
          >
            {cameraEnabled ? (
              <Camera className="size-6" />
            ) : (
              <CameraOff className="size-6" />
            )}
          </Button>
          <span className="text-xs opacity-80">
            {cameraEnabled ? "Tắt camera" : "Bật camera"}
          </span>
        </div>
      )}

      {status === "active" && conversationId && (
        <div className="flex flex-col items-center gap-2">
          <Button
            type="button"
            size="icon-lg"
            variant={chatOpen ? "default" : "outline"}
            className={cn(
              "size-14 rounded-full",
              isVideo && "border-white/40 bg-black/35 text-white hover:bg-white/20"
            )}
            aria-label="Chat trong cuộc gọi"
            title="Chat trong cuộc gọi"
            onClick={() => setChatOpen((value) => !value)}
          >
            <MessageSquare className="size-6" />
          </Button>
          <span className="text-xs opacity-80">Nhắn tin</span>
        </div>
      )}

      <div className="flex flex-col items-center gap-2">
        <Button
          type="button"
          size="icon-lg"
          className="size-14 rounded-full bg-destructive text-white hover:bg-destructive/90"
          aria-label="Kết thúc cuộc gọi"
          title="Kết thúc"
          onClick={hangUp}
        >
          <PhoneOff className="size-6" />
        </Button>
        <span className="text-xs opacity-80">
          {direction === "outgoing" && status === "outgoing" ? "Hủy gọi" : "Kết thúc"}
        </span>
      </div>
    </>
  );

  if (isVideo) {
    return (
      <Dialog open>
        <DialogContent
          showCloseButton={false}
          className="block h-[min(86vh,760px)] w-[calc(100vw-1rem)] max-w-5xl overflow-hidden border-0 bg-black p-0 text-white shadow-2xl sm:max-w-5xl"
          onEscapeKeyDown={(event) => event.preventDefault()}
          onPointerDownOutside={(event) => event.preventDefault()}
        >
          <div className="relative h-full w-full bg-slate-950">
            <StreamVideo
              stream={remoteStream}
              label={`Video của ${peer.displayName}`}
            />

            {!hasRemoteVideo && (
              <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center gap-4 bg-gradient-to-br from-slate-950 to-violet-950">
                <UserAvatar
                  type="profile"
                  name={peer.displayName}
                  avatarUrl={peer.avatarUrl ?? undefined}
                  className="size-28 border-4 border-white/15 shadow-2xl"
                />
                <p className="text-sm text-white/70">
                  {status === "active" ? "Camera của người dùng đang tắt" : statusText}
                </p>
              </div>
            )}

            <DialogHeader className="absolute inset-x-0 top-0 z-10 bg-gradient-to-b from-black/75 to-transparent p-5 text-left">
              <DialogTitle className="text-xl text-white">{peer.displayName}</DialogTitle>
              <DialogDescription className="text-white/75">
                {statusText}
              </DialogDescription>
            </DialogHeader>

            <div className={cn("absolute top-20 z-20 aspect-video w-32 overflow-hidden rounded-xl border border-white/30 bg-slate-900 shadow-2xl sm:w-52", chatOpen ? "left-4 right-auto sm:left-auto sm:right-[21rem]" : "right-4")}>
              {localStream && cameraEnabled ? (
                <StreamVideo
                  stream={localStream}
                  muted
                  mirror
                  label="Video của bạn"
                />
              ) : (
                <div className="flex h-full flex-col items-center justify-center gap-1 text-white/65">
                  <CameraOff />
                  <span className="text-[11px]">Camera đang tắt</span>
                </div>
              )}
            </div>

            {chatOpen && conversationId && (
              <InCallChatPanel
                conversationId={conversationId}
                currentUserId={currentUserId}
                mode="direct"
                recipientId={peer.id}
                senderName={(userId) =>
                  userId === currentUserId ? "Bạn" : peer.displayName
                }
                onClose={() => setChatOpen(false)}
                className="absolute inset-x-3 bottom-28 top-20 z-30 sm:left-auto sm:right-4 sm:w-80"
              />
            )}

            <div className="absolute inset-x-0 bottom-0 z-20 flex items-center justify-center gap-4 bg-gradient-to-t from-black/85 via-black/45 to-transparent px-4 pb-5 pt-16 text-white sm:gap-6">
              {status === "incoming" ? incomingActions : ongoingActions}
            </div>
          </div>
        </DialogContent>
      </Dialog>
    );
  }

  return (
    <Dialog open>
      <DialogContent
        showCloseButton={false}
        className={cn(
          "border-primary/20 bg-background/95 text-center shadow-2xl backdrop-blur-xl",
          chatOpen ? "max-w-2xl sm:max-w-2xl" : "max-w-sm"
        )}
        onEscapeKeyDown={(event) => event.preventDefault()}
        onPointerDownOutside={(event) => event.preventDefault()}
      >
        <DialogHeader className="items-center text-center sm:text-center">
          <div className="relative mb-2">
            <div className="absolute inset-0 animate-ping rounded-full bg-primary/20" />
            <UserAvatar
              type="profile"
              name={peer.displayName}
              avatarUrl={peer.avatarUrl ?? undefined}
              className="relative size-28 border-4 border-background shadow-xl"
            />
          </div>
          <DialogTitle className="text-2xl">{peer.displayName}</DialogTitle>
          <DialogDescription className="min-h-5 text-sm">
            {statusText}
          </DialogDescription>
        </DialogHeader>

        {audioPlaybackBlocked && (
          <Button
            type="button"
            variant="outline"
            className="mx-auto"
            onClick={onEnableAudio}
          >
            <Volume2 />
            Bật âm thanh
          </Button>
        )}

        {chatOpen && conversationId && (
          <InCallChatPanel
            conversationId={conversationId}
            currentUserId={currentUserId}
            mode="direct"
            recipientId={peer.id}
            senderName={(userId) =>
              userId === currentUserId ? "Bạn" : peer.displayName
            }
            onClose={() => setChatOpen(false)}
            className="h-[min(52vh,470px)] text-left"
          />
        )}

        <div className="flex items-center justify-center gap-5 pt-3">
          {status === "incoming" ? incomingActions : ongoingActions}
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default CallOverlay;
