import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";

import { useCallStore } from "@/stores/useCallStore";
import CallOverlay from "./CallOverlay";

const CallManager = () => {
  const remoteStream = useCallStore((state) => state.remoteStream);
  const mediaType = useCallStore((state) => state.mediaType);
  const audioRef = useRef<HTMLAudioElement>(null);
  const [audioPlaybackBlocked, setAudioPlaybackBlocked] = useState(false);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const audioStream = mediaType === "audio" ? remoteStream : null;
    audio.srcObject = audioStream;
    if (!audioStream) {
      audio.pause();
      setAudioPlaybackBlocked(false);
      return;
    }

    let cancelled = false;
    void audio
      .play()
      .then(() => {
        if (!cancelled) setAudioPlaybackBlocked(false);
      })
      .catch((error: unknown) => {
        if (cancelled) return;

        if (error instanceof DOMException && error.name === "NotAllowedError") {
          setAudioPlaybackBlocked(true);
          toast.warning("Trình duyệt đã chặn tự động phát âm thanh.");
          return;
        }

        if (!(error instanceof DOMException && error.name === "AbortError")) {
          toast.error("Không thể phát âm thanh cuộc gọi.");
        }
      });

    return () => {
      cancelled = true;
      audio.pause();
      if (audio.srcObject === audioStream) audio.srcObject = null;
    };
  }, [mediaType, remoteStream]);

  const enableRemoteAudio = useCallback(() => {
    const audio = audioRef.current;
    if (!audio) return;

    void audio
      .play()
      .then(() => setAudioPlaybackBlocked(false))
      .catch(() => toast.error("Không thể phát âm thanh cuộc gọi."));
  }, []);

  return (
    <>
      <audio ref={audioRef} autoPlay playsInline className="hidden" />
      <CallOverlay
        audioPlaybackBlocked={audioPlaybackBlocked}
        onEnableAudio={enableRemoteAudio}
      />
    </>
  );
};

export default CallManager;
