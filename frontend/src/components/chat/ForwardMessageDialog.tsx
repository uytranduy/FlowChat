import { useMemo, useState } from "react";
import { Check, Forward, LoaderCircle, Search } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { useAuthStore } from "@/stores/useAuthStore";
import { useChatStore } from "@/stores/useChatStore";
import type { Conversation, Message } from "@/types/chat";
import { Button } from "../ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "../ui/dialog";
import { Input } from "../ui/input";
import UserAvatar from "./UserAvatar";

interface ForwardMessageDialogProps {
  message: Message;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

function conversationName(conversation: Conversation, userId: string): string {
  if (conversation.type === "group") {
    return conversation.group?.name?.trim() || "Nhóm chat";
  }

  return (
    conversation.participants.find((participant) => participant._id !== userId)
      ?.displayName || "Cuộc trò chuyện"
  );
}

function conversationAvatar(
  conversation: Conversation,
  userId: string
): string | undefined {
  if (conversation.type === "group") return undefined;
  return (
    conversation.participants.find((participant) => participant._id !== userId)
      ?.avatarUrl ?? undefined
  );
}

const ForwardMessageDialog = ({
  message,
  open,
  onOpenChange,
}: ForwardMessageDialogProps) => {
  const user = useAuthStore((state) => state.user);
  const conversations = useChatStore((state) => state.conversations);
  const forwardMessage = useChatStore((state) => state.forwardMessage);
  const [query, setQuery] = useState("");
  const [selectedConversationId, setSelectedConversationId] = useState<
    string | null
  >(null);
  const [forwarding, setForwarding] = useState(false);

  const visibleConversations = useMemo(() => {
    if (!user) return [];
    const normalizedQuery = query.trim().toLocaleLowerCase();

    return conversations.filter((conversation) =>
      conversationName(conversation, user._id)
        .toLocaleLowerCase()
        .includes(normalizedQuery)
    );
  }, [conversations, query, user]);

  const handleOpenChange = (nextOpen: boolean) => {
    if (!nextOpen && !forwarding) {
      setQuery("");
      setSelectedConversationId(null);
    }
    onOpenChange(nextOpen);
  };

  const handleForward = async () => {
    if (!selectedConversationId || forwarding) return;

    setForwarding(true);
    try {
      await forwardMessage(message._id, selectedConversationId);
      toast.success("Đã chuyển tiếp tin nhắn.");
      setQuery("");
      setSelectedConversationId(null);
      onOpenChange(false);
    } catch (error) {
      console.error("Không thể chuyển tiếp tin nhắn", error);
      toast.error("Không thể chuyển tiếp tin nhắn. Vui lòng thử lại.");
    } finally {
      setForwarding(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Chuyển tiếp tin nhắn</DialogTitle>
          <DialogDescription>
            Chọn cuộc trò chuyện bạn muốn gửi tin nhắn này tới.
          </DialogDescription>
        </DialogHeader>

        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Tìm cuộc trò chuyện..."
            className="pl-9"
            autoFocus
          />
        </div>

        <div className="beautiful-scrollbar max-h-72 space-y-1 overflow-y-auto pr-1">
          {visibleConversations.map((conversation) => {
            const name = conversationName(conversation, user?._id ?? "");
            const selected = selectedConversationId === conversation._id;

            return (
              <button
                key={conversation._id}
                type="button"
                onClick={() => setSelectedConversationId(conversation._id)}
                className={cn(
                  "flex w-full items-center gap-3 rounded-lg border px-3 py-2 text-left transition-colors",
                  selected
                    ? "border-primary bg-primary/10"
                    : "border-transparent hover:bg-muted"
                )}
              >
                <UserAvatar
                  type="chat"
                  name={name}
                  avatarUrl={conversationAvatar(
                    conversation,
                    user?._id ?? ""
                  )}
                />
                <span className="min-w-0 flex-1 truncate text-sm font-medium">
                  {name}
                </span>
                {selected && <Check className="size-4 text-primary" />}
              </button>
            );
          })}

          {visibleConversations.length === 0 && (
            <p className="py-8 text-center text-sm text-muted-foreground">
              Không tìm thấy cuộc trò chuyện phù hợp.
            </p>
          )}
        </div>

        <DialogFooter>
          <Button
            type="button"
            variant="outline"
            onClick={() => handleOpenChange(false)}
            disabled={forwarding}
          >
            Hủy
          </Button>
          <Button
            type="button"
            onClick={() => void handleForward()}
            disabled={!selectedConversationId || forwarding}
          >
            {forwarding ? (
              <LoaderCircle className="animate-spin" />
            ) : (
              <Forward />
            )}
            Chuyển tiếp
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

export default ForwardMessageDialog;
