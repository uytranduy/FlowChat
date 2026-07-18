import { useEffect, useMemo, useState } from "react";
import { Bell, BellRing, Check, ExternalLink } from "lucide-react";
import { useAuthStore } from "@/stores/useAuthStore";
import { useChatStore } from "@/stores/useChatStore";
import type { Conversation } from "@/types/chat";
import { Button } from "../ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "../ui/popover";
import GroupChatAvatar from "./GroupChatAvatar";
import UserAvatar from "./UserAvatar";

function conversationName(conversation: Conversation, userId: string): string {
  if (conversation.type === "group") {
    return conversation.group?.name || "Nhóm chat";
  }
  return (
    conversation.participants.find((participant) => participant._id !== userId)
      ?.displayName || "Cuộc trò chuyện"
  );
}

function lastMessagePreview(conversation: Conversation): string {
  const lastMessage = conversation.lastMessage;
  if (!lastMessage) return "Cuộc trò chuyện mới";
  if (lastMessage.isRecalled) return "Tin nhắn đã được thu hồi";
  if (lastMessage.messageType === "attachment" || lastMessage.attachment) {
    switch (lastMessage.attachment?.kind) {
      case "image":
        return "Đã gửi một ảnh";
      case "video":
        return "Đã gửi một video";
      default:
        return "Đã gửi một tệp";
    }
  }
  if (lastMessage.messageType === "call") return "Cuộc gọi";
  return lastMessage.content?.trim() || "Tin nhắn mới";
}

const NotificationCenter = () => {
  const user = useAuthStore((state) => state.user);
  const conversations = useChatStore((state) => state.conversations);
  const setActiveConversation = useChatStore(
    (state) => state.setActiveConversation
  );
  const refreshLatestMessages = useChatStore(
    (state) => state.refreshLatestMessages
  );
  const [open, setOpen] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission | "unsupported">(
    () =>
      typeof window !== "undefined" && "Notification" in window
        ? Notification.permission
        : "unsupported"
  );

  const unreadConversations = useMemo(() => {
    if (!user) return [];
    return conversations.filter(
      (conversation) => (conversation.unreadCounts?.[user._id] ?? 0) > 0
    );
  }, [conversations, user]);
  const totalUnread = useMemo(() => {
    if (!user) return 0;
    return unreadConversations.reduce(
      (total, conversation) =>
        total + (conversation.unreadCounts?.[user._id] ?? 0),
      0
    );
  }, [unreadConversations, user]);

  useEffect(() => {
    document.title = totalUnread > 0 ? `(${totalUnread}) FlowChat` : "FlowChat";
    return () => {
      document.title = "FlowChat";
    };
  }, [totalUnread]);

  if (!user) return null;

  const openConversation = async (conversationId: string) => {
    setOpen(false);
    setActiveConversation(conversationId);
    await refreshLatestMessages(conversationId);
  };

  const requestBrowserNotifications = async () => {
    if (!("Notification" in window)) return;
    const nextPermission = await Notification.requestPermission();
    setPermission(nextPermission);
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="relative size-8 rounded-full text-white hover:bg-white/15 hover:text-white"
          aria-label={
            totalUnread > 0
              ? `${totalUnread} tin nhắn chưa đọc`
              : "Không có tin nhắn chưa đọc"
          }
          title="Thông báo"
        >
          {totalUnread > 0 ? (
            <BellRing className="size-4 animate-pulse" />
          ) : (
            <Bell className="size-4" />
          )}
          {totalUnread > 0 && (
            <span className="absolute -right-1 -top-1 flex min-w-4 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-4 text-white ring-2 ring-primary">
              {totalUnread > 99 ? "99+" : totalUnread}
            </span>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-80 p-0">
        <div className="flex items-center justify-between border-b px-4 py-3">
          <div>
            <h3 className="font-semibold text-foreground">Thông báo</h3>
            <p className="text-xs text-muted-foreground">
              {totalUnread > 0
                ? `${totalUnread} tin nhắn chưa đọc`
                : "Bạn đã xem hết tin nhắn"}
            </p>
          </div>
          {totalUnread === 0 && <Check className="size-5 text-green-500" />}
        </div>

        <div className="max-h-80 overflow-y-auto p-2 beautiful-scrollbar">
          {unreadConversations.length === 0 ? (
            <div className="px-4 py-8 text-center">
              <Bell className="mx-auto mb-2 size-8 text-muted-foreground/50" />
              <p className="text-sm text-muted-foreground">
                Chưa có thông báo mới.
              </p>
            </div>
          ) : (
            unreadConversations.map((conversation) => {
              const unreadCount = conversation.unreadCounts[user._id] ?? 0;
              const otherUser = conversation.participants.find(
                (participant) => participant._id !== user._id
              );

              return (
                <button
                  type="button"
                  key={conversation._id}
                  onClick={() => void openConversation(conversation._id)}
                  className="flex w-full items-center gap-3 rounded-xl p-2 text-left transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <div className="shrink-0">
                    {conversation.type === "group" ? (
                      <GroupChatAvatar
                        participants={conversation.participants}
                        type="chat"
                      />
                    ) : (
                      <UserAvatar
                        type="chat"
                        name={otherUser?.displayName || "FlowChat"}
                        avatarUrl={otherUser?.avatarUrl ?? undefined}
                      />
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-foreground">
                      {conversationName(conversation, user._id)}
                    </p>
                    <p className="truncate text-xs text-muted-foreground">
                      {lastMessagePreview(conversation)}
                    </p>
                  </div>
                  <span className="flex min-w-5 items-center justify-center rounded-full bg-primary px-1.5 text-[11px] font-bold leading-5 text-primary-foreground">
                    {unreadCount > 99 ? "99+" : unreadCount}
                  </span>
                </button>
              );
            })
          )}
        </div>

        {permission === "default" && (
          <div className="border-t p-2">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="w-full justify-start"
              onClick={() => void requestBrowserNotifications()}
            >
              <ExternalLink className="size-4" />
              Bật thông báo khi rời tab
            </Button>
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
};

export default NotificationCenter;
