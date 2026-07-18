import { useAuthStore } from "@/stores/useAuthStore";
import { useChatStore } from "@/stores/useChatStore";
import type { Conversation } from "@/types/chat";
import ChatCard from "./ChatCard";
import UnreadCountBadge from "./UnreadCountBadge";
import GroupChatAvatar from "./GroupChatAvatar";
import { cn } from "@/lib/utils";
import { chatService } from "@/services/chatService";
import { toast } from "sonner";

const GroupChatCard = ({ convo }: { convo: Conversation }) => {
  const { user } = useAuthStore();
  const {
    activeConversationId,
    setActiveConversation,
    refreshLatestMessages,
    updateConversation,
  } = useChatStore();

  if (!user) return null;

  const unreadCount = convo.unreadCounts?.[user._id] ?? 0;
  const name = convo.group?.name ?? "";
  const last = convo.lastMessage;
  const senderName =
    last?.sender?._id === user._id
      ? "Bạn"
      : last?.sender?.displayName ||
        convo.participants.find((participant) => {
          const senderId =
            typeof last?.senderId === "string"
              ? last.senderId
              : last?.senderId?._id;
          return participant._id === senderId;
        })?.displayName;
  const attachmentPreview =
    last?.attachment?.kind === "image"
      ? "📷 Ảnh"
      : last?.attachment?.kind === "video"
        ? "🎬 Video"
        : last?.attachment
          ? `📎 ${last.attachment.fileName || "Tệp đính kèm"}`
          : null;
  const preview = last?.isRecalled
    ? "Tin nhắn đã thu hồi"
    : last?.messageType === "call"
      ? "Cuộc gọi"
      : attachmentPreview
        ? `${attachmentPreview}${last?.content?.trim() ? ` · ${last.content.trim()}` : ""}`
        : last?.content?.trim() || `${convo.participants.length} thành viên`;
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
      name={name}
      timestamp={
        convo.lastMessage?.createdAt
          ? new Date(convo.lastMessage.createdAt)
          : undefined
      }
      isActive={activeConversationId === convo._id}
      onSelect={handleSelectConversation}
      unreadCount={unreadCount}
      infoLabel="Xem thông tin nhóm"
      onOpenInfo={handleOpenInfo}
      onMarkAsRead={unreadCount > 0 ? handleMarkAsRead : undefined}
      leftSection={
        <>
          {unreadCount > 0 && <UnreadCountBadge unreadCount={unreadCount} />}
          <GroupChatAvatar
            participants={convo.participants}
            type="chat"
          />
        </>
      }
      subtitle={
        <p
          className={cn(
            "truncate text-sm",
            unreadCount > 0
              ? "font-medium text-foreground"
              : "text-muted-foreground"
          )}
        >
          {last && senderName ? `${senderName}: ` : ""}
          {preview}
        </p>
      }
    />
  );
};

export default GroupChatCard;
