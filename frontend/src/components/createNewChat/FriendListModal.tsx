import { useFriendStore } from "@/stores/useFriendStore";
import { DialogContent, DialogHeader, DialogTitle } from "../ui/dialog";
import { LoaderCircle, MessageCircleMore, Search, Users } from "lucide-react";
import { Card } from "../ui/card";
import UserAvatar from "../chat/UserAvatar";
import { useChatStore } from "@/stores/useChatStore";
import { useAuthStore } from "@/stores/useAuthStore";
import { useMemo, useState } from "react";
import { Input } from "../ui/input";
import type { Conversation, LastMessage } from "@/types/chat";
import { toast } from "sonner";

function lastMessagePreview(last: LastMessage | null): string {
  if (!last) return "Chưa có tin nhắn nào trong cuộc trò chuyện này";
  if (last.isRecalled) return "Tin nhắn đã thu hồi";
  if (last.messageType === "call") return last.content || "Cuộc gọi";
  if (last.attachment?.kind === "image") return "📷 Ảnh";
  if (last.attachment?.kind === "video") return "🎬 Video";
  if (last.attachment) return `📎 ${last.attachment.fileName}`;
  return last.content?.trim() || "Chưa có tin nhắn nào trong cuộc trò chuyện này";
}

const FriendListModal = ({ onSelected }: { onSelected?: () => void }) => {
  const { friends } = useFriendStore();
  const userId = useAuthStore((state) => state.user?._id);
  const conversations = useChatStore((state) => state.conversations);
  const createConversation = useChatStore((state) => state.createConversation);
  const setActiveConversation = useChatStore((state) => state.setActiveConversation);
  const refreshLatestMessages = useChatStore((state) => state.refreshLatestMessages);
  const [query, setQuery] = useState("");
  const [openingId, setOpeningId] = useState<string | null>(null);

  const directByFriendId = useMemo(() => {
    const result = new Map<string, Conversation>();
    for (const conversation of conversations) {
      if (conversation.type !== "direct") continue;
      const other = conversation.participants.find(
        (participant) => participant._id !== userId
      );
      if (!other) continue;
      const previous = result.get(other._id);
      const currentTime = new Date(
        conversation.lastMessage?.createdAt || conversation.updatedAt || 0
      ).getTime();
      const previousTime = new Date(
        previous?.lastMessage?.createdAt || previous?.updatedAt || 0
      ).getTime();
      const currentHasMessages = Boolean(conversation.lastMessage);
      const previousHasMessages = Boolean(previous?.lastMessage);
      if (
        !previous ||
        (currentHasMessages && !previousHasMessages) ||
        (currentHasMessages === previousHasMessages && currentTime > previousTime)
      ) {
        result.set(other._id, conversation);
      }
    }
    return result;
  }, [conversations, userId]);

  const filteredFriends = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("vi");
    if (!normalized) return friends;
    return friends.filter(
      (friend) =>
        friend.displayName.toLocaleLowerCase("vi").includes(normalized) ||
        friend.username.toLocaleLowerCase("vi").includes(normalized)
    );
  }, [friends, query]);

  const handleAddConversation = async (friendId: string) => {
    if (openingId) return;
    setOpeningId(friendId);
    try {
      const existing = directByFriendId.get(friendId);
      if (existing) {
        setActiveConversation(existing._id);
        await refreshLatestMessages(existing._id);
      } else {
        const conversation = await createConversation("direct", "", [friendId]);
        await refreshLatestMessages(conversation._id);
      }
      onSelected?.();
    } catch (error) {
      toast.error(
        error instanceof Error
          ? error.message
          : "Không thể mở cuộc trò chuyện."
      );
    } finally {
      setOpeningId(null);
    }
  };

  return (
    <DialogContent className="glass max-w-md">
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2 text-xl capitalize">
          <MessageCircleMore className="size-5" />
          cuộc hội thoại
        </DialogTitle>
      </DialogHeader>

      <div className="space-y-4">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Tìm bạn bè theo tên hoặc @username"
            className="pl-9"
            autoFocus
          />
        </div>

        <h1 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          danh sách bạn bè
        </h1>

        <div className="space-y-2 max-h-60 overflow-y-auto">
          {filteredFriends.map((friend) => {
            const conversation = directByFriendId.get(friend._id);
            const opening = openingId === friend._id;
            return (
            <Card
              onClick={() => handleAddConversation(friend._id)}
              key={friend._id}
              className="cursor-pointer p-3 transition-smooth hover:shadow-soft glass hover:bg-muted/30 group/friendCard"
            >
              <div className="flex items-center gap-3">
                {/* avatar */}
                <div className="relative">
                  <UserAvatar
                    type="sidebar"
                    name={friend.displayName}
                    avatarUrl={friend.avatarUrl}
                  />
                </div>

                {/* info */}
                <div className="flex-1 min-w-0 flex flex-col">
                  <h2 className="font-semibold text-sm truncate">
                    {friend.displayName}
                  </h2>
                  <span className="truncate text-xs text-muted-foreground">
                    {lastMessagePreview(conversation?.lastMessage ?? null)}
                  </span>
                </div>
                {opening && <LoaderCircle className="size-5 animate-spin" />}
              </div>
            </Card>
            );
          })}

          {filteredFriends.length === 0 && (
            <div className="text-center py-8 text-muted-foreground">
              <Users className="size-12 mx-auto mb-3 opacity-50" />
              {friends.length === 0
                ? "Chưa có bạn bè. Hãy kết bạn để bắt đầu trò chuyện."
                : "Không tìm thấy người bạn phù hợp."}
            </div>
          )}
        </div>
      </div>
    </DialogContent>
  );
};

export default FriendListModal;
