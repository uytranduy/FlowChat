import { useEffect, useMemo, useRef, useState } from "react";
import { FileText, LoaderCircle, Paperclip, Send, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { chatService } from "@/services/chatService";
import { useChatStore } from "@/stores/useChatStore";
import type { Message } from "@/types/chat";

const EMPTY_MESSAGES: Message[] = [];

interface InCallChatPanelProps {
  conversationId: string;
  currentUserId?: string;
  mode: "direct" | "group";
  recipientId?: string;
  senderName: (userId: string) => string | undefined;
  onClose: () => void;
  className?: string;
}

export default function InCallChatPanel({
  conversationId,
  currentUserId,
  mode,
  recipientId,
  senderName,
  onClose,
  className = "",
}: InCallChatPanelProps) {
  const [text, setText] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [sending, setSending] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const messages = useChatStore(
    (state) => state.messages[conversationId]?.items ?? EMPTY_MESSAGES
  );
  const refreshMessages = useChatStore((state) => state.refreshLatestMessages);
  const recentMessages = useMemo(() => messages.slice(-40), [messages]);

  useEffect(() => {
    void refreshMessages(conversationId);
    const timer = window.setInterval(
      () => void refreshMessages(conversationId),
      4_000
    );
    return () => window.clearInterval(timer);
  }, [conversationId, refreshMessages]);

  const submit = async () => {
    const content = text.trim();
    if ((!content && !file) || sending) return;
    if (mode === "direct" && !recipientId) {
      toast.error("Không xác định được người nhận.");
      return;
    }

    setSending(true);
    try {
      if (mode === "group") {
        await chatService.sendGroupMessage(conversationId, content, file ?? undefined);
      } else {
        await chatService.sendDirectMessage(
          recipientId!,
          content,
          file ?? undefined,
          conversationId
        );
      }
      setText("");
      setFile(null);
      if (fileInput.current) fileInput.current.value = "";
      await refreshMessages(conversationId);
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : "Không thể gửi tin nhắn."
      );
    } finally {
      setSending(false);
    }
  };

  return (
    <aside
      className={`flex min-h-0 flex-col overflow-hidden rounded-2xl border border-white/10 bg-slate-950/95 text-white shadow-2xl ${className}`}
    >
      <div className="flex items-center justify-between border-b border-white/10 px-3 py-2">
        <div>
          <p className="font-semibold">Chat trong cuộc gọi</p>
          <p className="text-xs text-slate-400">
            Có thể gửi tin nhắn, ảnh, video và tệp
          </p>
        </div>
        <Button size="icon" variant="ghost" onClick={onClose} title="Đóng chat">
          <X />
        </Button>
      </div>

      <div className="flex-1 space-y-2 overflow-y-auto p-3">
        {recentMessages.length === 0 && (
          <p className="py-8 text-center text-sm text-slate-400">
            Chưa có tin nhắn.
          </p>
        )}
        {recentMessages.map((message) => (
          <CallChatMessage
            key={message._id}
            message={message}
            own={message.senderId === currentUserId}
            senderName={senderName(message.senderId)}
          />
        ))}
      </div>

      {file && (
        <div className="mx-3 mb-2 flex items-center gap-2 rounded-xl bg-white/10 px-3 py-2 text-xs">
          <FileText className="size-4 shrink-0" />
          <span className="min-w-0 flex-1 truncate">{file.name}</span>
          <button
            type="button"
            className="text-slate-300 hover:text-white"
            onClick={() => {
              setFile(null);
              if (fileInput.current) fileInput.current.value = "";
            }}
            aria-label="Bỏ tệp đã chọn"
          >
            <X className="size-4" />
          </button>
        </div>
      )}

      <div className="flex gap-2 border-t border-white/10 p-3">
        <input
          ref={fileInput}
          type="file"
          className="hidden"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
        <Button
          type="button"
          size="icon"
          variant="secondary"
          disabled={sending}
          title="Gửi ảnh, video hoặc tệp"
          onClick={() => fileInput.current?.click()}
        >
          <Paperclip />
        </Button>
        <input
          value={text}
          onChange={(event) => setText(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              void submit();
            }
          }}
          placeholder="Nhắn tin..."
          className="min-w-0 flex-1 rounded-xl border border-white/10 bg-slate-900 px-3 py-2 text-sm outline-none focus:border-violet-400"
        />
        <Button
          size="icon"
          disabled={(!text.trim() && !file) || sending}
          onClick={() => void submit()}
        >
          {sending ? <LoaderCircle className="animate-spin" /> : <Send />}
        </Button>
      </div>
    </aside>
  );
}

function CallChatMessage({
  message,
  own,
  senderName,
}: {
  message: Message;
  own: boolean;
  senderName?: string;
}) {
  const attachment = message.attachment;
  const preview = message.isRecalled
    ? "Tin nhắn đã thu hồi"
    : message.messageType === "call"
      ? "📞 Lịch sử cuộc gọi"
      : message.content?.trim() || "";

  return (
    <div className={`flex ${own ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[90%] overflow-hidden rounded-2xl px-3 py-2 text-sm ${
          own ? "bg-violet-600" : "bg-slate-800"
        }`}
      >
        {!own && (
          <p className="mb-0.5 text-[11px] font-semibold text-violet-300">
            {senderName || "Thành viên"}
          </p>
        )}
        {attachment?.kind === "image" && (
          <a href={attachment.url} target="_blank" rel="noreferrer">
            <img
              src={attachment.url}
              alt={attachment.fileName}
              className="mb-1 max-h-44 w-full rounded-lg object-contain"
            />
          </a>
        )}
        {attachment?.kind === "video" && (
          <video
            src={attachment.url}
            controls
            playsInline
            preload="metadata"
            className="mb-1 max-h-44 w-full rounded-lg bg-black"
          />
        )}
        {attachment?.kind === "file" && (
          <a
            href={attachment.url}
            target="_blank"
            rel="noreferrer"
            className="mb-1 flex items-center gap-2 underline"
          >
            <FileText className="size-4 shrink-0" />
            <span className="truncate">{attachment.fileName}</span>
          </a>
        )}
        {preview && <p className="break-words">{preview}</p>}
      </div>
    </div>
  );
}
