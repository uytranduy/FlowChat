import type { Conversation } from "@/types/chat";
import ChatCard from "./ChatCard";
import { useAuthStore } from "@/stores/useAuthStore";
import { useChatStore } from "@/stores/useChatStore";
import { cn } from "@/lib/utils";
import UserAvatar from "./UserAvatar";
import StatusBadge from "./StatusBadge";
import UnreadCountBadge from "./UnreadCountBadge";
import { useSocketStore } from "@/stores/useSocketStore";
import { chatService } from "@/services/chatService";
import { toast } from "sonner";

const DirectMessageCard = ({ convo }: { convo: Conversation }) => {
  const { user } = useAuthStore();
  const {
    activeConversationId,
    setActiveConversation,
    refreshLatestMessages,
    updateConversation,
  } = useChatStore();
  const { onlineUsers } = useSocketStore();

  if (!user) return null;

  const otherUser = convo.participants.find((p) => p._id !== user._id);
  if (!otherUser) return null;

  const unreadCount = convo.unreadCounts?.[user._id] ?? 0;
  const last = convo.lastMessage;
  const isCallPreview =
    last?.messageType === "call" ||
    last?.content === "Cuộc gọi thoại" ||
    last?.content === "Cuộc gọi video";
  const callDuration = last?.call?.durationSeconds ?? 0;
  const durationPreview =
    callDuration > 0
      ? ` · ${Math.floor(callDuration / 60)}p ${callDuration % 60}s`
      : "";
  const populatedSenderId =
    typeof last?.senderId === "string" ? last.senderId : last?.senderId?._id;
  const lastSenderId = last?.sender?._id ?? populatedSenderId;
  const attachmentPreview =
    last?.attachment?.kind === "image"
      ? "📷 Ảnh"
      : last?.attachment?.kind === "video"
        ? "🎬 Video"
        : last?.attachment
          ? `📎 ${last.attachment.fileName || "Tệp đính kèm"}`
          : null;
  const lastMessage = isCallPreview
    ? `${last?.content ?? "Cuộc gọi"} ${
        lastSenderId === user._id ? "đi" : "đến"
      }${durationPreview}`
    : last?.isRecalled
      ? "Tin nhắn đã thu hồi"
      : attachmentPreview
        ? `${attachmentPreview}${last?.content?.trim() ? ` · ${last.content.trim()}` : ""}`
        : (last?.content ?? "");

  const handleSelectConversation = async (id: string) => {
    setActiveConversation(id);
    await refreshLatestMessages(id);
  };
  const handleOpenInfo = () => {
    setActiveConversation(convo._id);
    void refreshLatestMessages(convo._id);
    window.setTimeout(() => {
      window.dispatchEvent(
        new CustomEvent("flowchat:open-conversation-info", {
          detail: { conversationId: convo._id },
        })
      );
    }, 0);
  };
  const handleMarkAsRead = async () => {
    try {
      await chatService.markAsSeen(convo._id);
      updateConversation({
        _id: convo._id,
        unreadCounts: { ...convo.unreadCounts, [user._id]: 0 },
      });
    } catch {
      toast.error("Không thể đánh dấu cuộc trò chuyện là đã đọc.");
    }
  };

  return (
    <ChatCard
      convoId={convo._id}
      name={otherUser.displayName ?? ""}
      timestamp={
        convo.lastMessage?.createdAt
          ? new Date(convo.lastMessage.createdAt)
          : undefined
      }
      isActive={activeConversationId === convo._id}
      onSelect={handleSelectConversation}
      unreadCount={unreadCount}
      infoLabel="Xem thông tin người dùng"
      onOpenInfo={handleOpenInfo}
      onMarkAsRead={unreadCount > 0 ? handleMarkAsRead : undefined}
      leftSection={
        <>
          <UserAvatar
            type="sidebar"
            name={otherUser.displayName ?? ""}
            avatarUrl={otherUser.avatarUrl ?? undefined}
          />
          <StatusBadge
            status={
              onlineUsers.includes(otherUser?._id ?? "") ? "online" : "offline"
            }
          />
          {unreadCount > 0 && <UnreadCountBadge unreadCount={unreadCount} />}
        </>
      }
      subtitle={
        <p
          className={cn(
            "text-sm truncate",
            unreadCount > 0 ? "font-medium text-foreground" : "text-muted-foreground"
          )}
        >
          {lastMessage}
        </p>
      }
    />
  );
};

export default DirectMessageCard;
