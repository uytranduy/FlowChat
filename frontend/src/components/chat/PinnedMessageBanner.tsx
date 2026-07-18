import { useCallback, useEffect, useMemo, useState } from "react";
import { Ellipsis, MessageCircle, PinOff } from "lucide-react";
import { toast } from "sonner";

import { chatService } from "@/services/chatService";
import { useAuthStore } from "@/stores/useAuthStore";
import { useChatStore } from "@/stores/useChatStore";
import { useSocketStore } from "@/stores/useSocketStore";
import type { Conversation, Message } from "@/types/chat";
import { Button } from "../ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import MessageFinderDialog from "./MessageFinderDialog";

function preview(message: Message): string {
  if (message.attachment) {
    const attachment =
      message.attachment.kind === "image"
        ? "📷 Ảnh"
        : message.attachment.kind === "video"
          ? "🎬 Video"
          : `📎 ${message.attachment.fileName}`;
    return message.content?.trim()
      ? `${attachment} · ${message.content.trim()}`
      : attachment;
  }
  if (message.messageType === "call") return "📞 Lịch sử cuộc gọi";
  return message.content?.trim() || "Tin nhắn";
}

export default function PinnedMessageBanner({
  conversation,
}: {
  conversation: Conversation;
}) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [listOpen, setListOpen] = useState(false);
  const [unpinning, setUnpinning] = useState(false);
  const updateMessagePin = useChatStore((state) => state.updateMessagePin);
  const currentUserId = useAuthStore((state) => state.user?._id);
  const socket = useSocketStore((state) => state.socket);

  const load = useCallback(async () => {
    try {
      setMessages(await chatService.fetchPinnedMessages(conversation._id));
    } catch (error) {
      console.error("Không thể tải thanh tin nhắn đã ghim", error);
    }
  }, [conversation._id]);

  useEffect(() => {
    void load();
    const handleChange = (event: Event) => {
      const id = (event as CustomEvent<{ conversationId?: string }>).detail
        ?.conversationId;
      if (!id || id === conversation._id) void load();
    };
    window.addEventListener("flowchat:pins-changed", handleChange);
    const timer = window.setInterval(() => void load(), 10_000);
    return () => {
      window.removeEventListener("flowchat:pins-changed", handleChange);
      window.clearInterval(timer);
    };
  }, [conversation._id, load]);

  useEffect(() => {
    if (!socket) return;
    const handlePinUpdate = (payload: { conversationId?: string }) => {
      if (payload?.conversationId === conversation._id) void load();
    };
    socket.on("message-pin:updated", handlePinUpdate);
    return () => {
      socket.off("message-pin:updated", handlePinUpdate);
    };
  }, [conversation._id, load, socket]);

  const names = useMemo(
    () =>
      new Map(
        conversation.participants.map((participant) => [
          participant._id,
          participant.displayName,
        ])
      ),
    [conversation.participants]
  );
  const current = messages[0];
  if (!current) return null;

  const jumpToCurrent = () => {
    window.dispatchEvent(
      new CustomEvent("flowchat:jump-message", {
        detail: {
          conversationId: conversation._id,
          messageId: current._id,
        },
      })
    );
  };

  const unpinCurrent = async () => {
    if (unpinning) return;
    setUnpinning(true);
    try {
      await updateMessagePin(conversation._id, current._id, false);
      setMessages((items) => items.filter((item) => item._id !== current._id));
      toast.success("Đã bỏ ghim tin nhắn.");
    } catch (error) {
      console.error("Không thể bỏ ghim tin nhắn", error);
      toast.error("Không thể bỏ ghim tin nhắn.");
    } finally {
      setUnpinning(false);
    }
  };

  return (
    <>
      <div className="z-[9] mx-2 flex items-center gap-3 rounded-lg border bg-background px-3 py-2 shadow-sm">
        <MessageCircle className="size-5 shrink-0 text-primary" />
        <button
          type="button"
          className="min-w-0 flex-1 text-left"
          title="Chuyển đến tin nhắn đã ghim"
          onClick={jumpToCurrent}
        >
          <span className="block text-sm font-semibold">Tin nhắn</span>
          <span className="block truncate text-sm">
            <strong>{names.get(current.senderId) || "Thành viên"}:</strong>{" "}
            {preview(current)}
          </span>
        </button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() => setListOpen(true)}
        >
          {messages.length > 1 ? `+${messages.length - 1} ghim` : "1 ghim"}
        </Button>
        {current.pinnedBy === currentUserId && <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button type="button" variant="ghost" size="icon" className="size-8">
              <Ellipsis />
              <span className="sr-only">Tùy chọn tin nhắn đã ghim</span>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem
              disabled={unpinning}
              onSelect={() => void unpinCurrent()}
            >
              <PinOff />
              Bỏ ghim tin nhắn này
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>}
      </div>
      <MessageFinderDialog
        conversation={conversation}
        mode="pinned"
        open={listOpen}
        onOpenChange={setListOpen}
      />
    </>
  );
}
