import { useChatStore } from "@/stores/useChatStore";
import ChatWelcomeScreen from "./ChatWelcomeScreen";
import { SidebarInset } from "../ui/sidebar";
import ChatWindowHeader from "./ChatWindowHeader";
import ChatWindowBody from "./ChatWindowBody";
import MessageInput from "./MessageInput";
import { useCallback, useEffect, useState } from "react";
import ChatWindowSkeleton from "../skeleton/ChatWindowSkeleton";
import { useAuthStore } from "@/stores/useAuthStore";
import { friendService } from "@/services/friendService";
import type { FriendRelationship } from "@/types/user";
import MessageRequestBanner from "./MessageRequestBanner";
import { useSocketStore } from "@/stores/useSocketStore";
import { AlertTriangle } from "lucide-react";

const ChatWindowLayout = () => {
  const {
    activeConversationId,
    conversations,
    messageLoading: loading,
    markAsSeen,
  } = useChatStore();

  const selectedConvo =
    conversations.find((c) => c._id === activeConversationId) ?? null;
  const user = useAuthStore((state) => state.user);
  const relationshipRevision = useSocketStore((state) => state.relationshipRevision);
  const [relationship, setRelationship] = useState<FriendRelationship | null>(null);
  const otherUser = selectedConvo?.type === "direct"
    ? selectedConvo.participants.find((participant) => participant._id !== user?._id)
    : undefined;
  const refreshRelationship = useCallback(async () => {
    if (!otherUser) { setRelationship(null); return; }
    setRelationship(await friendService.getRelationship(otherUser._id));
  }, [otherUser]);

  useEffect(() => {
    void refreshRelationship();
  }, [refreshRelationship, relationshipRevision]);
  useEffect(() => {
    if (selectedConvo?.type === "direct") void refreshRelationship();
  }, [selectedConvo?.lastMessage?._id, selectedConvo?.type, refreshRelationship]);

  useEffect(() => {
    if (!selectedConvo) {
      return;
    }

    const markSeen = async () => {
      try {
        await markAsSeen();
      } catch (error) {
        console.error("Lỗi khi markSeen", error);
      }
    };

    markSeen();
  }, [markAsSeen, selectedConvo]);

  if (!selectedConvo) {
    return <ChatWelcomeScreen />;
  }

  if (loading) {
    return <ChatWindowSkeleton />;
  }

  return (
    <SidebarInset className="flex flex-col h-full flex-1 overflow-hidden rounded-sm shadow-md">
      {/* Header */}
      <ChatWindowHeader chat={selectedConvo} relationship={relationship} onRelationshipChanged={refreshRelationship} />

      {/* Body */}
      <div className="flex-1 overflow-y-auto bg-primary-foreground">
        <ChatWindowBody />
      </div>

      {/* Footer */}
      {selectedConvo.type === "group" && selectedConvo.group?.dissolvedAt ? (
        <div className="flex items-center justify-center gap-2 border-t border-destructive/20 bg-destructive/10 px-4 py-3 text-sm font-medium text-destructive">
          <AlertTriangle className="size-4" />
          Nhóm đã bị giải tán. Bạn không thể nhắn tin hoặc gọi điện.
        </div>
      ) : (
        <>
          {otherUser && <MessageRequestBanner relationship={relationship} otherUser={otherUser} onChanged={refreshRelationship} />}
          <MessageInput selectedConvo={selectedConvo} relationship={relationship} onRelationshipChanged={refreshRelationship} />
        </>
      )}
    </SidebarInset>
  );
};

export default ChatWindowLayout;
