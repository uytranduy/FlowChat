import { useEffect, useMemo, useState } from "react";
import { FileText, LoaderCircle, Pin, Search } from "lucide-react";
import { toast } from "sonner";

import { chatService } from "@/services/chatService";
import { useSocketStore } from "@/stores/useSocketStore";
import type { Conversation, Message } from "@/types/chat";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "../ui/dialog";
import { Input } from "../ui/input";

interface MessageFinderDialogProps {
  conversation: Conversation;
  mode: "search" | "pinned";
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSelectMessage?: (message: Message) => void | Promise<void>;
}

function messagePreview(message: Message): string {
  if (message.isRecalled) return "Tin nhắn đã thu hồi";
  if (message.attachment) {
    const prefix =
      message.attachment.kind === "image"
        ? "📷 Ảnh"
        : message.attachment.kind === "video"
          ? "🎬 Video"
          : `📎 ${message.attachment.fileName}`;
    return message.content?.trim()
      ? `${prefix} · ${message.content.trim()}`
      : prefix;
  }
  if (message.messageType === "call") return "📞 Lịch sử cuộc gọi";
  return message.content?.trim() || "Tin nhắn";
}

export default function MessageFinderDialog({
  conversation,
  mode,
  open,
  onOpenChange,
  onSelectMessage,
}: MessageFinderDialogProps) {
  const [query, setQuery] = useState("");
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(false);
  const [pinRevision, setPinRevision] = useState(0);
  const socket = useSocketStore((state) => state.socket);
  const title = mode === "search" ? "Tìm kiếm tin nhắn" : "Tin nhắn đã ghim";

  useEffect(() => {
    if (!open) {
      setQuery("");
      setMessages([]);
      return;
    }

    const normalized = query.trim();
    if (mode === "search" && !normalized) {
      setMessages([]);
      setLoading(false);
      return;
    }

    let cancelled = false;
    const timer = window.setTimeout(
      () => {
        setLoading(true);
        const request =
          mode === "pinned"
            ? chatService.fetchPinnedMessages(conversation._id)
            : chatService.searchMessages(conversation._id, normalized);
        void request
          .then((result) => {
            if (!cancelled) setMessages(result);
          })
          .catch((error) => {
            console.error("Không thể tải danh sách tin nhắn", error);
            if (!cancelled) toast.error("Không thể tải danh sách tin nhắn.");
          })
          .finally(() => {
            if (!cancelled) setLoading(false);
          });
      },
      mode === "search" ? 300 : 0
    );
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [conversation._id, mode, open, pinRevision, query]);

  useEffect(() => {
    if (!socket || mode !== "pinned") return;
    const handlePinUpdate = (payload: { conversationId?: string }) => {
      if (payload?.conversationId === conversation._id) {
        setPinRevision((revision) => revision + 1);
      }
    };
    socket.on("message-pin:updated", handlePinUpdate);
    return () => {
      socket.off("message-pin:updated", handlePinUpdate);
    };
  }, [conversation._id, mode, socket]);

  const participantNames = useMemo(
    () =>
      new Map(
        conversation.participants.map((participant) => [
          participant._id,
          participant.displayName,
        ])
      ),
    [conversation.participants]
  );

  const jumpTo = (message: Message) => {
    onOpenChange(false);
    if (onSelectMessage) {
      void onSelectMessage(message);
      return;
    }
    window.dispatchEvent(
      new CustomEvent("flowchat:jump-message", {
        detail: { conversationId: conversation._id, messageId: message._id },
      })
    );
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="flex max-h-[80vh] flex-col sm:max-w-xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {mode === "search" ? <Search /> : <Pin />}
            {title}
          </DialogTitle>
          <DialogDescription>
            Chọn một kết quả để chuyển đến vị trí tin nhắn trong cuộc trò chuyện.
          </DialogDescription>
        </DialogHeader>

        {mode === "search" && (
          <div className="relative">
            <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              autoFocus
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Nhập nội dung hoặc tên tệp..."
              className="pl-9"
            />
          </div>
        )}

        <div className="min-h-36 flex-1 space-y-2 overflow-y-auto">
          {loading && (
            <div className="flex h-32 items-center justify-center">
              <LoaderCircle className="animate-spin text-primary" />
            </div>
          )}
          {!loading && messages.length === 0 && (
            <div className="flex h-32 flex-col items-center justify-center gap-2 text-sm text-muted-foreground">
              {mode === "search" ? <Search /> : <Pin />}
              {mode === "search" && !query.trim()
                ? "Nhập từ khóa để tìm kiếm."
                : mode === "pinned"
                  ? "Chưa có tin nhắn nào được ghim."
                  : "Không tìm thấy tin nhắn phù hợp."}
            </div>
          )}
          {!loading &&
            messages.map((message) => (
              <button
                key={message._id}
                type="button"
                className="flex w-full items-start gap-3 rounded-xl border p-3 text-left transition-colors hover:bg-muted"
                onClick={() => jumpTo(message)}
              >
                <FileText className="mt-0.5 size-4 shrink-0 text-primary" />
                <span className="min-w-0 flex-1">
                  <span className="block text-xs font-semibold text-primary">
                    {participantNames.get(message.senderId) || "Thành viên"}
                  </span>
                  <span className="line-clamp-2 block break-words text-sm">
                    {messagePreview(message)}
                  </span>
                  <span className="mt-1 block text-xs text-muted-foreground">
                    {new Date(message.createdAt).toLocaleString("vi-VN")}
                  </span>
                </span>
              </button>
            ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
