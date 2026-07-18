import { useChatStore } from "@/stores/useChatStore";
import type { Conversation } from "@/types/chat";
import { SidebarTrigger } from "../ui/sidebar";
import { useAuthStore } from "@/stores/useAuthStore";
import { Separator } from "../ui/separator";
import UserAvatar from "./UserAvatar";
import StatusBadge from "./StatusBadge";
import GroupChatAvatar from "./GroupChatAvatar";
import { useSocketStore } from "@/stores/useSocketStore";
import { Button } from "../ui/button";
import { ChevronRight, Phone, PhoneCall, Search, Video } from "lucide-react";
import { useCallStore } from "@/stores/useCallStore";
import { useEffect, useState } from "react";
import ConversationInfoDialog from "./ConversationInfoDialog";
import type { FriendRelationship } from "@/types/user";
import { useGroupCallStore } from "@/stores/useGroupCallStore";
import { presenceText } from "@/lib/presence";
import MessageFinderDialog from "./MessageFinderDialog";

const ChatWindowHeader = ({ chat, relationship, onRelationshipChanged }: { chat?: Conversation; relationship?: FriendRelationship | null; onRelationshipChanged?: () => void | Promise<void> }) => {
  const { conversations, activeConversationId } = useChatStore();
  const { user } = useAuthStore();
  const { onlineUsers, isConnected, lastSeenByUser } = useSocketStore();
  const callStatus = useCallStore((state) => state.status);
  const startCall = useCallStore((state) => state.startCall);
  const [infoOpen, setInfoOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [presenceNow, setPresenceNow] = useState(() => Date.now());
  const groupCallStatus = useGroupCallStore((state) => state.status);
  const startGroupCall = useGroupCallStore((state) => state.start);
  const activeGroupRoom = useGroupCallStore((state) => state.activeRoom);
  const checkActiveGroupCall = useGroupCallStore((state) => state.checkActive);

  let otherUser;

  chat = chat ?? conversations.find((c) => c._id === activeConversationId);

  useEffect(() => {
    if (!chat || chat.type !== "group" || !isConnected) return;
    void checkActiveGroupCall(chat._id);
    const timer = window.setInterval(() => {
      void checkActiveGroupCall(chat!._id);
    }, 10_000);
    return () => window.clearInterval(timer);
  }, [chat, isConnected, checkActiveGroupCall]);

  useEffect(() => {
    const timer = window.setInterval(() => setPresenceNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    const openConversationInfo = (event: Event) => {
      const conversationId = (event as CustomEvent<{ conversationId?: string }>)
        .detail?.conversationId;
      if (conversationId && conversationId === chat?._id) {
        setInfoOpen(true);
      }
    };

    window.addEventListener(
      "flowchat:open-conversation-info",
      openConversationInfo
    );
    return () =>
      window.removeEventListener(
        "flowchat:open-conversation-info",
        openConversationInfo
      );
  }, [chat?._id]);

  if (!chat) {
    return (
      <header className="md:hidden sticky top-0 z-10 flex items-center gap-2 px-4 py-2 w-full">
        <SidebarTrigger className="-ml-1 text-foreground" />
      </header>
    );
  }

  if (chat.type === "direct") {
    const otherUsers = chat.participants.filter((p) => p._id !== user?._id);
    otherUser = otherUsers.length > 0 ? otherUsers[0] : null;

    if (!user || !otherUser) return;
  }

  return (
    <header className="sticky top-0 z-10 px-4 py-2 flex items-center bg-background">
      <div className="flex items-center gap-2 w-full">
        <SidebarTrigger className="-ml-1 text-foreground" />
        <Separator
          orientation="vertical"
          className="mr-2 data-[orientation=vertical]:h-4"
        />

        <div className="p-2 w-full flex items-center gap-3">
          <button
            type="button"
            onClick={() => setInfoOpen(true)}
            className="group/info flex min-w-0 items-center gap-3 rounded-xl p-1 text-left transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            title={
              chat.type === "group"
                ? "Xem thông tin và thành viên nhóm"
                : "Xem thông tin người dùng"
            }
            aria-label={
              chat.type === "group"
                ? "Xem thông tin và thành viên nhóm"
                : "Xem thông tin người dùng"
            }
          >
            <div className="relative shrink-0">
              {chat.type === "direct" ? (
                <>
                  <UserAvatar
                    type={"sidebar"}
                    name={otherUser?.displayName || "FlowChat"}
                    avatarUrl={otherUser?.avatarUrl || undefined}
                  />
                  <StatusBadge
                    status={
                      onlineUsers.includes(otherUser?._id ?? "")
                        ? "online"
                        : "offline"
                    }
                  />
                </>
              ) : (
                <GroupChatAvatar
                  participants={chat.participants}
                  type="sidebar"
                />
              )}
            </div>

            <div className="min-w-0">
              <h2 className="truncate font-semibold text-foreground">
                {chat.type === "direct"
                  ? otherUser?.displayName
                  : chat.group?.name}
              </h2>
              <p className="truncate text-xs text-muted-foreground">
                {chat.type === "group"
                  ? chat.group?.dissolvedAt
                    ? "Nhóm đã bị giải tán · Xem thông tin"
                    : `${chat.participants.length} thành viên · Xem thông tin nhóm`
                  : `${presenceText({ isOnline: onlineUsers.includes(otherUser?._id ?? ""), lastSeenAt: otherUser ? lastSeenByUser[otherUser._id] ?? otherUser.lastSeenAt : null, presenceVisible: otherUser?.presenceVisible, now: presenceNow })} · Xem thông tin`}
              </p>
            </div>
            <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover/info:translate-x-0.5" />
          </button>

          {chat.type === "direct" && otherUser && (
            <div className="ml-auto flex items-center gap-1">
              <Button type="button" size="icon" variant="ghost" className="rounded-full" title="Tìm kiếm tin nhắn" aria-label="Tìm kiếm tin nhắn" onClick={() => setSearchOpen(true)}><Search /></Button>
              <Button
                type="button"
                size="icon"
                variant="ghost"
                className="rounded-full text-primary"
                disabled={!isConnected || callStatus !== "idle" || !relationship?.canCall}
                aria-label={`Gọi thoại cho ${otherUser.displayName}`}
                title={
                  isConnected
                    ? `Gọi thoại cho ${otherUser.displayName}`
                    : "Đang kết nối máy chủ cuộc gọi"
                }
                onClick={() =>
                  void startCall(
                    {
                      id: otherUser._id,
                      displayName: otherUser.displayName,
                      avatarUrl: otherUser.avatarUrl,
                    },
                    chat._id,
                    "audio"
                  )
                }
              >
                <Phone />
              </Button>
              <Button
                type="button"
                size="icon"
                variant="ghost"
                className="rounded-full text-primary"
                disabled={!isConnected || callStatus !== "idle" || !relationship?.canCall}
                aria-label={`Gọi video cho ${otherUser.displayName}`}
                title={
                  isConnected
                    ? `Gọi video cho ${otherUser.displayName}`
                    : "Đang kết nối máy chủ cuộc gọi"
                }
                onClick={() =>
                  void startCall(
                    {
                      id: otherUser._id,
                      displayName: otherUser.displayName,
                      avatarUrl: otherUser.avatarUrl,
                    },
                    chat._id,
                    "video"
                  )
                }
              >
                <Video />
              </Button>
            </div>
          )}
          {chat.type === "group" && !chat.group?.dissolvedAt && (
            <div className="ml-auto flex items-center gap-1">
              <Button type="button" size="icon" variant="ghost" className="rounded-full" title="Tìm kiếm tin nhắn" aria-label="Tìm kiếm tin nhắn" onClick={() => setSearchOpen(true)}><Search /></Button>
              {activeGroupRoom?.conversationId === chat._id ? (
                <Button type="button" variant="ghost" className="rounded-full text-emerald-600" disabled={!isConnected || callStatus !== "idle" || groupCallStatus !== "idle"} title="Tham gia lại cuộc gọi nhóm" onClick={() => void startGroupCall(chat!._id, chat!.group?.name || "Nhóm chat", activeGroupRoom.mediaType)}><PhoneCall /> Vào lại ({activeGroupRoom.participantCount})</Button>
              ) : (
                <>
                  <Button type="button" size="icon" variant="ghost" className="rounded-full text-primary" disabled={!isConnected || callStatus !== "idle" || groupCallStatus !== "idle"} title="Gọi thoại nhóm" onClick={() => void startGroupCall(chat!._id, chat!.group?.name || "Nhóm chat", "audio")}><Phone /></Button>
                  <Button type="button" size="icon" variant="ghost" className="rounded-full text-primary" disabled={!isConnected || callStatus !== "idle" || groupCallStatus !== "idle"} title="Gọi video nhóm" onClick={() => void startGroupCall(chat!._id, chat!.group?.name || "Nhóm chat", "video")}><Video /></Button>
                </>
              )}
            </div>
          )}
          {chat.type === "group" && chat.group?.dissolvedAt && (
            <div className="ml-auto flex items-center gap-1">
              <Button type="button" size="icon" variant="ghost" className="rounded-full" title="Tìm kiếm tin nhắn" aria-label="Tìm kiếm tin nhắn" onClick={() => setSearchOpen(true)}><Search /></Button>
            </div>
          )}
        </div>
      </div>
      <ConversationInfoDialog
        conversation={chat}
        open={infoOpen}
        onOpenChange={setInfoOpen}
        onRelationshipChanged={onRelationshipChanged}
      />
      <MessageFinderDialog
        conversation={chat}
        mode="search"
        open={searchOpen}
        onOpenChange={setSearchOpen}
      />
    </header>
  );
};

export default ChatWindowHeader;
