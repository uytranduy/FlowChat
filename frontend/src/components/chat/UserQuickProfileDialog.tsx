import { useEffect, useState } from "react";
import { Ban, Loader2, MessageCircle, Phone, ShieldCheck, Video } from "lucide-react";
import { toast } from "sonner";

import type { Conversation, Participant } from "@/types/chat";
import { blockService, type UserBlockStatus } from "@/services/blockService";
import { chatService } from "@/services/chatService";
import { useAuthStore } from "@/stores/useAuthStore";
import { useCallStore } from "@/stores/useCallStore";
import { useChatStore } from "@/stores/useChatStore";
import { useSocketStore } from "@/stores/useSocketStore";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "../ui/dialog";
import UserAvatar from "./UserAvatar";
import { friendService } from "@/services/friendService";
import type { FriendRelationship } from "@/types/user";
import { userService } from "@/services/userService";
import { presenceText } from "@/lib/presence";

interface UserQuickProfileActionsProps {
  participant: Participant;
  onDone?: () => void;
  onRelationshipChanged?: () => void | Promise<void>;
}

function errorText(error: unknown, fallback: string): string {
  return (
    error as { response?: { data?: { message?: string } } }
  ).response?.data?.message ?? fallback;
}

export function UserQuickProfileActions({ participant, onDone, onRelationshipChanged }: UserQuickProfileActionsProps) {
  const currentUser = useAuthStore((state) => state.user);
  const conversations = useChatStore((state) => state.conversations);
  const addConvo = useChatStore((state) => state.addConvo);
  const startCall = useCallStore((state) => state.startCall);
  const callStatus = useCallStore((state) => state.status);
  const connected = useSocketStore((state) => state.isConnected);
  const [blockStatus, setBlockStatus] = useState<UserBlockStatus | null>(null);
  const [relationship, setRelationship] = useState<FriendRelationship | null>(null);
  const [loadingStatus, setLoadingStatus] = useState(true);
  const [pending, setPending] = useState(false);
  const isMe = participant._id === currentUser?._id;

  useEffect(() => {
    let cancelled = false;
    if (isMe) {
      setLoadingStatus(false);
      return;
    }
    setLoadingStatus(true);
    void Promise.all([
      blockService.getStatus(participant._id),
      friendService.getRelationship(participant._id),
    ])
      .then(([status, nextRelationship]) => {
        if (!cancelled) {
          setBlockStatus(status);
          setRelationship(nextRelationship);
        }
      })
      .catch((error) => toast.error(errorText(error, "Không thể kiểm tra trạng thái chặn.")))
      .finally(() => { if (!cancelled) setLoadingStatus(false); });
    return () => { cancelled = true; };
  }, [isMe, participant._id]);

  const ensureDirectConversation = async (): Promise<Conversation> => {
    const existing = conversations.find(
      (conversation) =>
        conversation.type === "direct" &&
        conversation.participants.some((member) => member._id === participant._id)
    );
    if (existing) {
      addConvo(existing);
      return existing;
    }
    const created = await chatService.createConversation("direct", "", [participant._id]);
    addConvo(created);
    useSocketStore.getState().socket?.emit("join-conversation", created._id);
    return created;
  };

  const openChat = async () => {
    if (blockStatus?.isBlocked || pending) return;
    setPending(true);
    try {
      await ensureDirectConversation();
      onDone?.();
    } catch (error) {
      toast.error(errorText(error, "Không thể mở cuộc trò chuyện riêng."));
    } finally {
      setPending(false);
    }
  };

  const call = async (mediaType: "audio" | "video") => {
    if (blockStatus?.isBlocked || pending || callStatus !== "idle") return;
    setPending(true);
    try {
      const conversation = await ensureDirectConversation();
      onDone?.();
      await startCall(
        { id: participant._id, displayName: participant.displayName, avatarUrl: participant.avatarUrl },
        conversation._id,
        mediaType
      );
    } catch (error) {
      toast.error(errorText(error, "Không thể bắt đầu cuộc gọi."));
    } finally {
      setPending(false);
    }
  };

  const toggleBlock = async () => {
    if (pending) return;
    const unblock = Boolean(blockStatus?.isBlockedByMe);
    if (!unblock && !window.confirm(`Chặn ${participant.displayName}? Hai người sẽ không thể nhắn tin hoặc gọi riêng.`)) return;
    setPending(true);
    try {
      const status = unblock
        ? await blockService.unblock(participant._id)
        : await blockService.block(participant._id);
      setBlockStatus(status);
      useSocketStore.setState((state) => ({
        relationshipRevision: state.relationshipRevision + 1,
      }));
      await onRelationshipChanged?.();
      toast.success(unblock ? "Đã huỷ chặn người dùng." : "Đã chặn người dùng.");
    } catch (error) {
      toast.error(errorText(error, unblock ? "Không thể huỷ chặn." : "Không thể chặn người dùng."));
    } finally {
      setPending(false);
    }
  };

  if (isMe) return <p className="text-center text-sm text-muted-foreground">Đây là tài khoản của bạn.</p>;

  const cannotInteract = loadingStatus || Boolean(blockStatus?.isBlocked);
  const cannotCall = cannotInteract || !relationship?.canCall;
  return (
    <div className="space-y-3">
      {blockStatus?.hasBlockedMe && (
        <p className="rounded-lg bg-destructive/10 px-3 py-2 text-sm text-destructive">
          Người này đã chặn bạn. Bạn không thể nhắn tin hoặc gọi riêng.
        </p>
      )}
      {blockStatus?.isBlockedByMe && (
        <p className="rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">
          Bạn đã chặn người này. Hãy huỷ chặn để tiếp tục liên hệ.
        </p>
      )}
      <div className="grid grid-cols-3 gap-2">
        <Button variant="outline" className="h-auto flex-col gap-1 py-3" disabled={cannotInteract || pending} onClick={() => void openChat()}>
          <MessageCircle /> <span>Nhắn riêng</span>
        </Button>
        <Button variant="outline" className="h-auto flex-col gap-1 py-3" disabled={cannotCall || pending || !connected || callStatus !== "idle"} onClick={() => void call("audio")}>
          <Phone /> <span>Gọi thoại</span>
        </Button>
        <Button variant="outline" className="h-auto flex-col gap-1 py-3" disabled={cannotCall || pending || !connected || callStatus !== "idle"} onClick={() => void call("video")}>
          <Video /> <span>Gọi video</span>
        </Button>
      </div>
      {!loadingStatus && !relationship?.isFriend && !blockStatus?.isBlocked && (
        <p className="text-center text-xs text-muted-foreground">
          Hai người cần chấp nhận lời mời nhắn tin trước khi có thể gọi điện.
        </p>
      )}
      <Button variant={blockStatus?.isBlockedByMe ? "outline" : "destructive"} className="w-full" disabled={loadingStatus || pending} onClick={() => void toggleBlock()}>
        {pending ? <Loader2 className="animate-spin" /> : blockStatus?.isBlockedByMe ? <ShieldCheck /> : <Ban />}
        {blockStatus?.isBlockedByMe ? "Huỷ chặn người dùng" : "Chặn người dùng"}
      </Button>
    </div>
  );
}

export default function UserQuickProfileDialog({ participant, open, onOpenChange, onRelationshipChanged }: { participant: Participant | null; open: boolean; onOpenChange: (open: boolean) => void; onRelationshipChanged?: () => void | Promise<void> }) {
  const [publicProfile, setPublicProfile] = useState<Participant | null>(participant);
  const onlineUsers = useSocketStore((state) => state.onlineUsers);
  const lastSeenByUser = useSocketStore((state) => state.lastSeenByUser);
  const [presenceNow, setPresenceNow] = useState(() => Date.now());

  useEffect(() => {
    if (!open) return;
    const timer = window.setInterval(() => setPresenceNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, [open]);

  useEffect(() => {
    setPublicProfile(participant);
    if (!open || !participant) return;
    let cancelled = false;
    void userService.getPublicUser(participant._id).then((user) => {
      if (!cancelled) {
        setPublicProfile({
          ...participant,
          displayName: user.displayName,
          username: user.username,
          avatarUrl: user.avatarUrl ?? null,
          bio: user.bio ?? null,
          isOnline: user.isOnline,
          lastSeenAt: user.lastSeenAt,
          presenceVisible: user.presenceVisible,
        });
      }
    }).catch(() => {
      // Conversation data remains a safe fallback if refreshing the public profile fails.
    });
    return () => { cancelled = true; };
  }, [open, participant]);

  if (!participant) return null;
  const profile = publicProfile ?? participant;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Thông tin người dùng</DialogTitle>
          <DialogDescription>Liên hệ riêng hoặc quản lý quyền tương tác.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col items-center py-2 text-center">
          <UserAvatar type="profile" name={profile.displayName} avatarUrl={profile.avatarUrl ?? undefined} />
          <h3 className="mt-3 text-xl font-bold">{profile.displayName}</h3>
          {profile.username && <p className="text-sm text-muted-foreground">@{profile.username}</p>}
          <p className="mt-1 text-xs text-muted-foreground">{presenceText({ isOnline: onlineUsers.includes(profile._id) || profile.isOnline === true, lastSeenAt: lastSeenByUser[profile._id] ?? profile.lastSeenAt, presenceVisible: profile.presenceVisible, now: presenceNow })}</p>
          {profile.bio?.trim() ? <p className="mt-2 whitespace-pre-wrap text-sm text-muted-foreground">{profile.bio}</p> : <p className="mt-2 text-sm text-muted-foreground">Người dùng chưa thêm lời giới thiệu.</p>}
        </div>
        <UserQuickProfileActions participant={profile} onDone={() => onOpenChange(false)} onRelationshipChanged={onRelationshipChanged} />
      </DialogContent>
    </Dialog>
  );
}
