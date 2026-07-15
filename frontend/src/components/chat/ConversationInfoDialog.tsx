import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, CalendarDays, Crown, Loader2, LogOut, Search, Trash2, UserPlus, Users } from "lucide-react";
import { useAuthStore } from "@/stores/useAuthStore";
import { useSocketStore } from "@/stores/useSocketStore";
import type { Conversation, Participant } from "@/types/chat";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "../ui/dialog";
import { Input } from "../ui/input";
import GroupChatAvatar from "./GroupChatAvatar";
import StatusBadge from "./StatusBadge";
import UserAvatar from "./UserAvatar";
import UserQuickProfileDialog, { UserQuickProfileActions } from "./UserQuickProfileDialog";
import { userService } from "@/services/userService";
import { presenceText } from "@/lib/presence";
import { useFriendStore } from "@/stores/useFriendStore";
import { useChatStore } from "@/stores/useChatStore";
import { chatService } from "@/services/chatService";
import { Button } from "../ui/button";
import { toast } from "sonner";
import { Switch } from "../ui/switch";

interface ConversationInfoDialogProps {
  conversation: Conversation;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onRelationshipChanged?: () => void | Promise<void>;
}

function formatDate(value?: string): string {
  if (!value) return "Không rõ";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Không rõ";
  return new Intl.DateTimeFormat("vi-VN", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(date);
}

function PublicUserDetails({
  participant,
  online,
  now,
  lastSeenAt,
}: {
  participant: Participant;
  online: boolean;
  now: number;
  lastSeenAt?: string | null;
}) {
  return (
    <div className="flex flex-col items-center text-center">
      <div className="relative">
        <UserAvatar
          type="profile"
          name={participant.displayName || "FlowChat"}
          avatarUrl={participant.avatarUrl ?? undefined}
        />
        <StatusBadge status={online ? "online" : "offline"} />
      </div>
      <h3 className="mt-3 text-xl font-bold text-foreground">
        {participant.displayName}
      </h3>
      {participant.username && (
        <p className="text-sm text-muted-foreground">@{participant.username}</p>
      )}
      <p className="mt-3 max-w-sm text-sm text-muted-foreground">
        {participant.bio?.trim() || "Người dùng chưa thêm lời giới thiệu."}
      </p>
      <div className="mt-4 flex items-center gap-2 rounded-full bg-muted px-3 py-1.5 text-xs text-muted-foreground">
        <span
          className={`size-2 rounded-full ${online ? "bg-green-500" : "bg-slate-400"}`}
        />
        {presenceText({ isOnline: online, lastSeenAt: lastSeenAt ?? participant.lastSeenAt, presenceVisible: participant.presenceVisible, now })}
      </div>
    </div>
  );
}

const ConversationInfoDialog = ({
  conversation,
  open,
  onOpenChange,
  onRelationshipChanged,
}: ConversationInfoDialogProps) => {
  const user = useAuthStore((state) => state.user);
  const onlineUsers = useSocketStore((state) => state.onlineUsers);
  const lastSeenByUser = useSocketStore((state) => state.lastSeenByUser);
  const [query, setQuery] = useState("");
  const [selectedParticipant, setSelectedParticipant] = useState<Participant | null>(null);
  const [directProfile, setDirectProfile] = useState<Participant | null>(null);
  const [presenceNow, setPresenceNow] = useState(() => Date.now());
  const isGroup = conversation.type === "group";
  const [addMemberOpen, setAddMemberOpen] = useState(false);
  const [groupPending, setGroupPending] = useState<string | null>(null);
  const friends = useFriendStore((state) => state.friends);
  const getFriends = useFriendStore((state) => state.getFriends);
  const updateConversation = useChatStore((state) => state.updateConversation);
  const removeConversation = useChatStore((state) => state.removeConversation);
  const clearConversationMessages = useChatStore((state) => state.clearConversationMessages);
  const refreshLatestMessages = useChatStore((state) => state.refreshLatestMessages);
  const otherUser = conversation.participants.find(
    (participant) => participant._id !== user?._id
  );
  const displayedOtherUser = directProfile ?? otherUser;
  const currentUserIsOwner = isGroup && conversation.group?.createdBy?.toString() === user?._id;
  const isDissolved = Boolean(conversation.group?.dissolvedAt);
  const membersCanInvite = conversation.group?.allowMembersToInvite !== false;
  const currentUserCanInvite = !isDissolved && (currentUserIsOwner || membersCanInvite);
  const participantIds = useMemo(
    () => new Set(conversation.participants.map((participant) => participant._id)),
    [conversation.participants]
  );
  const availableFriends = friends.filter((friend) => !participantIds.has(friend._id));

  useEffect(() => {
    if (open && currentUserCanInvite) void getFriends();
  }, [currentUserCanInvite, getFriends, open]);

  const addMember = async (userId: string) => {
    if (groupPending) return;
    setGroupPending(userId);
    try {
      const updated = await chatService.addGroupMember(conversation._id, userId);
      updateConversation(updated);
      toast.success("Đã thêm thành viên vào nhóm.");
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể thêm thành viên.");
    } finally {
      setGroupPending(null);
    }
  };

  const transferOwner = async (participant: Participant) => {
    if (groupPending || !window.confirm(`Chuyển quyền trưởng nhóm cho ${participant.displayName}?`)) return;
    setGroupPending(participant._id);
    try {
      const updated = await chatService.transferGroupOwnership(conversation._id, participant._id);
      updateConversation(updated);
      toast.success(`Đã chuyển quyền trưởng nhóm cho ${participant.displayName}.`);
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể chuyển quyền trưởng nhóm.");
    } finally {
      setGroupPending(null);
    }
  };

  const changeInvitePermission = async (allowMembersToInvite: boolean) => {
    if (groupPending) return;
    setGroupPending("settings");
    try {
      const updated = await chatService.updateGroupInvitePermission(
        conversation._id,
        allowMembersToInvite
      );
      updateConversation(updated);
      toast.success(
        allowMembersToInvite
          ? "Mọi thành viên có thể mời thêm người."
          : "Chỉ trưởng nhóm có thể mời thêm người."
      );
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể cập nhật quyền mời.");
    } finally {
      setGroupPending(null);
    }
  };

  const leaveGroup = async () => {
    if (groupPending || !window.confirm(`Bạn có chắc muốn rời ${conversation.group?.name || "nhóm này"}?`)) return;
    setGroupPending("leave");
    try {
      await chatService.leaveGroup(conversation._id);
      removeConversation(conversation._id);
      onOpenChange(false);
      toast.success("Bạn đã rời nhóm.");
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể rời nhóm.");
    } finally {
      setGroupPending(null);
    }
  };

  const dissolveGroup = async () => {
    if (groupPending || !window.confirm(`Giải tán ${conversation.group?.name || "nhóm này"}? Toàn bộ lịch sử tin nhắn sẽ bị xóa và không thể khôi phục.`)) return;
    setGroupPending("dissolve");
    try {
      const updated = await chatService.dissolveGroup(conversation._id);
      updateConversation(updated);
      clearConversationMessages(conversation._id);
      await refreshLatestMessages(conversation._id);
      toast.success("Nhóm đã được giải tán.");
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể giải tán nhóm.");
    } finally {
      setGroupPending(null);
    }
  };

  const removeDissolvedGroup = async () => {
    if (groupPending || !window.confirm("Xóa nhóm đã giải tán khỏi danh sách chat của bạn?")) return;
    setGroupPending("remove");
    try {
      await chatService.removeDissolvedGroup(conversation._id);
      removeConversation(conversation._id);
      onOpenChange(false);
      toast.success("Đã xóa nhóm khỏi danh sách.");
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể xóa nhóm.");
    } finally {
      setGroupPending(null);
    }
  };

  useEffect(() => {
    setDirectProfile(null);
    if (!open || isGroup || !otherUser) return;
    let cancelled = false;
    void userService.getPublicUser(otherUser._id).then((profile) => {
      if (!cancelled) {
        setDirectProfile({
          ...otherUser,
          displayName: profile.displayName,
          username: profile.username,
          avatarUrl: profile.avatarUrl ?? null,
          bio: profile.bio ?? null,
          isOnline: profile.isOnline,
          lastSeenAt: profile.lastSeenAt,
          presenceVisible: profile.presenceVisible,
        });
      }
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [isGroup, open, otherUser]);

  useEffect(() => {
    if (!open) return;
    setPresenceNow(Date.now());
    const timer = window.setInterval(() => setPresenceNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, [open]);
  const normalizedQuery = query.trim().toLocaleLowerCase("vi");
  const filteredParticipants = useMemo(
    () =>
      conversation.participants.filter((participant) => {
        if (!normalizedQuery) return true;
        return [participant.displayName, participant.username]
          .filter(Boolean)
          .some((value) =>
            value!.toLocaleLowerCase("vi").includes(normalizedQuery)
          );
      }),
    [conversation.participants, normalizedQuery]
  );

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        onOpenChange(nextOpen);
        if (!nextOpen) setQuery("");
      }}
    >
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>
            {isGroup ? "Thông tin nhóm" : "Thông tin người dùng"}
          </DialogTitle>
          <DialogDescription>
            {isGroup
              ? "Xem thông tin và các thành viên trong cuộc trò chuyện."
              : "Thông tin công khai của người đang trò chuyện với bạn."}
          </DialogDescription>
        </DialogHeader>

        {isGroup ? (
          <div className="space-y-5">
            <div className="flex flex-col items-center rounded-2xl bg-primary/5 p-5 text-center">
              <GroupChatAvatar
                participants={conversation.participants}
                type="profile"
              />
              <h3 className="mt-3 text-xl font-bold text-foreground">
                {conversation.group?.name || "Nhóm chat"}
              </h3>
              <p className="mt-1 flex items-center gap-1.5 text-sm text-muted-foreground">
                <Users className="size-4" />
                {conversation.participants.length} thành viên
              </p>
              <p className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground">
                <CalendarDays className="size-3.5" />
                Tạo ngày {formatDate(conversation.createdAt)}
              </p>
              {isDissolved && (
                <p className="mt-3 flex items-center gap-2 rounded-full bg-destructive/10 px-3 py-1.5 text-sm font-medium text-destructive">
                  <AlertTriangle className="size-4" /> Nhóm đã bị giải tán
                </p>
              )}
            </div>

            <div className="space-y-3">
              {currentUserIsOwner && !isDissolved && (
                <div className="flex items-center justify-between gap-3 rounded-xl border bg-muted/30 p-3">
                  <div>
                    <p className="text-sm font-medium">Cho phép thành viên mời thêm người</p>
                    <p className="text-xs text-muted-foreground">Khi tắt, chỉ trưởng nhóm có thể thêm thành viên.</p>
                  </div>
                  <Switch
                    checked={membersCanInvite}
                    disabled={Boolean(groupPending)}
                    onCheckedChange={(checked) => void changeInvitePermission(checked)}
                    aria-label="Cho phép mọi thành viên mời thêm người"
                  />
                </div>
              )}
              <div className="flex items-center justify-between">
                <h4 className="font-semibold text-foreground">
                  Thành viên ({conversation.participants.length})
                </h4>
                {currentUserCanInvite && (
                  <Button size="sm" variant="outline" onClick={() => setAddMemberOpen((value) => !value)}>
                    <UserPlus /> Thêm thành viên
                  </Button>
                )}
              </div>
              {currentUserCanInvite && addMemberOpen && (
                <div className="max-h-52 space-y-1 overflow-y-auto rounded-xl border bg-muted/30 p-2">
                  {availableFriends.length === 0 ? (
                    <p className="p-3 text-center text-sm text-muted-foreground">Không còn bạn bè nào có thể thêm.</p>
                  ) : availableFriends.map((friend) => (
                    <div key={friend._id} className="flex items-center gap-2 rounded-lg p-2 hover:bg-muted">
                      <UserAvatar type="chat" name={friend.displayName} avatarUrl={friend.avatarUrl} />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium">{friend.displayName}</p>
                        <p className="truncate text-xs text-muted-foreground">@{friend.username}</p>
                      </div>
                      <Button size="sm" disabled={Boolean(groupPending)} onClick={() => void addMember(friend._id)}>
                        {groupPending === friend._id ? <Loader2 className="animate-spin" /> : <UserPlus />} Thêm
                      </Button>
                    </div>
                  ))}
                </div>
              )}
              <div className="relative">
                <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                  placeholder="Tìm thành viên..."
                  className="pl-9"
                />
              </div>
              <div className="max-h-72 space-y-1 overflow-y-auto pr-1 beautiful-scrollbar">
                {filteredParticipants.map((participant) => {
                  const isOwner =
                    conversation.group?.createdBy?.toString() ===
                    participant._id.toString();
                  const isCurrentUser = participant._id === user?._id;
                  const online = onlineUsers.includes(participant._id);

                  return (
                    <div key={participant._id} className="flex items-center gap-1 rounded-xl hover:bg-muted/70">
                    <button
                      type="button"
                      onClick={() => !isCurrentUser && setSelectedParticipant(participant)}
                      className="flex min-w-0 flex-1 items-center gap-3 rounded-xl p-2 text-left disabled:cursor-default"
                      disabled={isCurrentUser}
                    >
                      <div className="relative shrink-0">
                        <UserAvatar
                          type="chat"
                          name={participant.displayName || "FlowChat"}
                          avatarUrl={participant.avatarUrl ?? undefined}
                        />
                        <StatusBadge status={online ? "online" : "offline"} />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-1.5">
                          <p className="truncate text-sm font-medium text-foreground">
                            {participant.displayName}
                            {isCurrentUser ? " (Bạn)" : ""}
                          </p>
                          {isOwner && (
                            <Crown
                              className="size-4 shrink-0 text-amber-500"
                              aria-label="Trưởng nhóm"
                            />
                          )}
                        </div>
                        <p className="truncate text-xs text-muted-foreground">
                          {participant.username
                            ? `@${participant.username}`
                            : online
                              ? "Đang hoạt động"
                              : "Đang ngoại tuyến"}
                        </p>
                        {participant.bio && (
                          <p className="mt-0.5 truncate text-xs text-muted-foreground/80">
                            {participant.bio}
                          </p>
                        )}
                      </div>
                    </button>
                    {currentUserIsOwner && !isDissolved && !isCurrentUser && (
                      <Button size="sm" variant="ghost" disabled={Boolean(groupPending)} onClick={() => void transferOwner(participant)} title="Chuyển quyền trưởng nhóm">
                        {groupPending === participant._id ? <Loader2 className="animate-spin" /> : <Crown className="text-amber-500" />}
                        Chuyển quyền
                      </Button>
                    )}
                    </div>
                  );
                })}
                {filteredParticipants.length === 0 && (
                  <p className="py-6 text-center text-sm text-muted-foreground">
                    Không tìm thấy thành viên phù hợp.
                  </p>
                )}
              </div>
              {isDissolved ? (
                <Button type="button" variant="destructive" className="w-full" disabled={Boolean(groupPending)} onClick={() => void removeDissolvedGroup()}>
                  {groupPending === "remove" ? <Loader2 className="animate-spin" /> : <Trash2 />}
                  Xóa nhóm
                </Button>
              ) : (
                <>
                  <Button type="button" variant="outline" className="w-full text-destructive hover:text-destructive" disabled={Boolean(groupPending)} onClick={() => void leaveGroup()}>
                    {groupPending === "leave" ? <Loader2 className="animate-spin" /> : <LogOut />}
                    Rời nhóm
                  </Button>
                  {currentUserIsOwner && (
                    <Button type="button" variant="destructive" className="w-full" disabled={Boolean(groupPending)} onClick={() => void dissolveGroup()}>
                      {groupPending === "dissolve" ? <Loader2 className="animate-spin" /> : <Trash2 />}
                      Giải tán nhóm
                    </Button>
                  )}
                </>
              )}
            </div>
          </div>
        ) : displayedOtherUser ? (
          <div className="space-y-5 py-2">
            <PublicUserDetails
              participant={displayedOtherUser}
              online={onlineUsers.includes(displayedOtherUser._id) || displayedOtherUser.isOnline === true}
              now={presenceNow}
              lastSeenAt={lastSeenByUser[displayedOtherUser._id]}
            />
            <div className="rounded-xl border bg-muted/30 px-4 py-3">
              <p className="text-xs text-muted-foreground">
                Bắt đầu trò chuyện từ
              </p>
              <p className="mt-1 flex items-center gap-2 text-sm font-medium">
                <CalendarDays className="size-4 text-primary" />
                {formatDate(conversation.createdAt)}
              </p>
            </div>
            <UserQuickProfileActions
              participant={displayedOtherUser}
              onDone={() => onOpenChange(false)}
              onRelationshipChanged={onRelationshipChanged}
            />
          </div>
        ) : (
          <p className="py-8 text-center text-sm text-muted-foreground">
            Không tìm thấy thông tin người dùng.
          </p>
        )}
      </DialogContent>
      <UserQuickProfileDialog
        participant={selectedParticipant}
        open={Boolean(selectedParticipant)}
        onRelationshipChanged={onRelationshipChanged}
        onOpenChange={(nextOpen) => {
          if (!nextOpen) setSelectedParticipant(null);
        }}
      />
    </Dialog>
  );
};

export default ConversationInfoDialog;
