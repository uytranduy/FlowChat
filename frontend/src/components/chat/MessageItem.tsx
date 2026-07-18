import { cn, formatMessageTime } from "@/lib/utils";
import type {
  Conversation,
  Message,
  MessageAttachment,
  MessageReaction,
  MessageReplyReference,
  Participant,
} from "@/types/chat";
import UserAvatar from "./UserAvatar";
import { Card } from "../ui/card";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import {
  CircleSlash2,
  Download,
  EllipsisVertical,
  FileText,
  Forward,
  PhoneCall,
  PhoneMissed,
  Pin,
  PinOff,
  Reply,
  Smile,
  Undo2,
  Video,
  ZoomIn,
  ZoomOut,
} from "lucide-react";
import { useAuthStore } from "@/stores/useAuthStore";
import { useCallStore } from "@/stores/useCallStore";
import { useChatStore } from "@/stores/useChatStore";
import { useSocketStore } from "@/stores/useSocketStore";
import type { CallMediaType } from "@/types/call";
import { useState } from "react";
import { toast } from "sonner";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import { Popover, PopoverContent, PopoverTrigger } from "../ui/popover";
import ForwardMessageDialog from "./ForwardMessageDialog";
import UserQuickProfileDialog from "./UserQuickProfileDialog";
import { Dialog, DialogContent, DialogTitle } from "../ui/dialog";

interface MessageItemProps {
  message: Message;
  index: number;
  messages: Message[];
  selectedConvo: Conversation;
  lastMessageStatus: "delivered" | "seen";
  highlighted?: boolean;
  onJumpToMessage: (messageId: string) => void | Promise<void>;
}

function formatCallDuration(durationSeconds: number): string {
  const safeSeconds = Math.max(0, Math.floor(durationSeconds));
  const minutes = Math.floor(safeSeconds / 60);
  const seconds = safeSeconds % 60;
  return `${minutes} phút ${seconds} giây`;
}

function callResultLabel(
  reason: string | undefined,
  durationSeconds: number,
  isOutgoing: boolean
): string {
  const duration = formatCallDuration(durationSeconds);
  let result: string | null = null;

  switch (reason) {
    case "declined":
      result = isOutgoing ? "Người nhận đã từ chối" : "Bạn đã từ chối";
      break;
    case "canceled":
      result = isOutgoing ? "Bạn đã hủy cuộc gọi" : "Cuộc gọi nhỡ";
      break;
    case "no-answer":
      result = isOutgoing ? "Không có người trả lời" : "Cuộc gọi nhỡ";
      break;
    case "busy":
      result = "Người nhận đang bận";
      break;
    case "media-error":
      result = "Không thể sử dụng camera/microphone";
      break;
    case "connection-failed":
    case "disconnected":
      result = "Cuộc gọi bị gián đoạn";
      break;
    case "answered-elsewhere":
      result = "Đã trả lời trên thiết bị khác";
      break;
    default:
      break;
  }

  return result ? `${result} · ${duration}` : duration;
}

function CallMessageCard({
  message,
  selectedConvo,
}: {
  message: Message;
  selectedConvo: Conversation;
}) {
  const user = useAuthStore((state) => state.user);
  const callStatus = useCallStore((state) => state.status);
  const startCall = useCallStore((state) => state.startCall);
  const isConnected = useSocketStore((state) => state.isConnected);
  const call = message.call;
  const isOutgoing = call ? call.callerId === user?._id : Boolean(message.isOwn);
  const mediaType: CallMediaType =
    call?.mediaType ??
    (message.content?.toLocaleLowerCase().includes("video") ? "video" : "audio");
  const durationSeconds = call?.durationSeconds ?? 0;
  const otherUser = selectedConvo.participants.find(
    (participant) => participant._id !== user?._id
  );
  const isMissed =
    !isOutgoing &&
    (call?.reason === "no-answer" || call?.reason === "canceled");
  const Icon = isMissed ? PhoneMissed : mediaType === "video" ? Video : PhoneCall;

  return (
    <div className="min-w-60 space-y-3">
      <div className="flex items-center gap-3">
        <div
          className={cn(
            "flex size-10 shrink-0 items-center justify-center rounded-full",
            isMissed
              ? "bg-destructive/15 text-destructive"
              : "bg-primary/15 text-primary"
          )}
        >
          <Icon className="size-5" />
        </div>
        <div className="min-w-0">
          <p className="text-sm font-semibold">
            Cuộc gọi {mediaType === "video" ? "video" : "thoại"}{" "}
            {isOutgoing ? "đi" : "đến"}
          </p>
          <p className="text-xs text-muted-foreground">
            {callResultLabel(call?.reason, durationSeconds, isOutgoing)}
          </p>
        </div>
      </div>

      {selectedConvo.type === "direct" && otherUser && (
        <Button
          type="button"
          size="sm"
          variant="outline"
          className="w-full"
          disabled={!isConnected || callStatus !== "idle"}
          onClick={() =>
            void startCall(
              {
                id: otherUser._id,
                displayName: otherUser.displayName,
                avatarUrl: otherUser.avatarUrl,
              },
              selectedConvo._id,
              mediaType
            )
          }
        >
          {mediaType === "video" ? <Video /> : <PhoneCall />}
          Gọi lại
        </Button>
      )}
    </div>
  );
}

const quickReactions = ["👍", "❤️", "😂", "😮", "😢", "😡"] as const;

function replySenderName(
  replyTo: MessageReplyReference,
  conversation: Conversation,
  currentUserId?: string
): string {
  if (replyTo.senderId === currentUserId) return "Bạn";
  return (
    conversation.participants.find(
      (participant) => participant._id === replyTo.senderId
    )?.displayName ?? "Thành viên"
  );
}

function replyPreview(replyTo: MessageReplyReference): string {
  if (replyTo.isRecalled) return "Tin nhắn đã được thu hồi";
  if (replyTo.messageType === "call") return "Cuộc gọi";
  if (replyTo.messageType === "attachment") {
    if (replyTo.attachment?.kind === "image") return "Ảnh";
    if (replyTo.attachment?.kind === "video") return "Video";
    return replyTo.attachment?.fileName || "Tệp đính kèm";
  }
  return replyTo.content?.trim() || "Tin nhắn";
}

function formatAttachmentSize(sizeBytes: number): string {
  const safeSize = Math.max(0, sizeBytes || 0);
  if (safeSize < 1024) return `${safeSize} B`;
  if (safeSize < 1024 * 1024) return `${(safeSize / 1024).toFixed(1)} KB`;
  return `${(safeSize / (1024 * 1024)).toFixed(1)} MB`;
}

function AttachmentContent({
  attachment,
  caption,
  isOwn,
}: {
  attachment: MessageAttachment;
  caption?: string | null;
  isOwn: boolean;
}) {
  const [imageOpen, setImageOpen] = useState(false);
  const [zoom, setZoom] = useState(1);
  const captionElement = caption?.trim() ? (
    <p
      className={cn(
        "mt-2 break-words px-1 text-sm leading-relaxed",
        isOwn && "text-white"
      )}
    >
      {caption.trim()}
    </p>
  ) : null;

  if (attachment.kind === "image") {
    return (
      <div className="min-w-40">
        <button
          type="button"
          onClick={() => { setZoom(1); setImageOpen(true); }}
          className="group/attachment block overflow-hidden rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          title="Phóng to ảnh"
        >
          <img
            src={attachment.url}
            alt={attachment.fileName || "Ảnh đã gửi"}
            loading="lazy"
            className="max-h-80 w-full min-w-40 object-contain transition-transform duration-200 group-hover/attachment:scale-[1.01]"
          />
        </button>
        {captionElement}
        <Dialog open={imageOpen} onOpenChange={setImageOpen}>
          <DialogContent className="h-[94vh] w-[96vw] max-w-none overflow-hidden border-0 bg-black/95 p-0 text-white">
            <DialogTitle className="sr-only">{attachment.fileName || "Xem ảnh"}</DialogTitle>
            <div className="absolute left-1/2 top-4 z-20 flex -translate-x-1/2 gap-2 rounded-full bg-black/60 p-1">
              <Button type="button" size="icon" variant="ghost" className="text-white" disabled={zoom <= 0.5} onClick={() => setZoom((value) => Math.max(.5, value - .25))}><ZoomOut /></Button>
              <span className="min-w-14 self-center text-center text-sm">{Math.round(zoom * 100)}%</span>
              <Button type="button" size="icon" variant="ghost" className="text-white" disabled={zoom >= 3} onClick={() => setZoom((value) => Math.min(3, value + .25))}><ZoomIn /></Button>
            </div>
            <div className="flex h-full w-full items-center justify-center overflow-auto p-10">
              <img src={attachment.url} alt={attachment.fileName || "Ảnh đã gửi"} className="max-h-full max-w-full select-none object-contain transition-transform" style={{ transform: `scale(${zoom})` }} />
            </div>
          </DialogContent>
        </Dialog>
      </div>
    );
  }

  if (attachment.kind === "video") {
    return (
      <div className="min-w-56">
        <video
          src={attachment.url}
          controls
          preload="metadata"
          playsInline
          className="max-h-80 w-full rounded-lg bg-black"
          aria-label={attachment.fileName || "Video đã gửi"}
        >
          Trình duyệt của bạn không hỗ trợ phát video.
        </video>
        <div
          className={cn(
            "mt-1 flex items-center justify-between gap-2 px-1 text-[11px]",
            isOwn ? "text-white/75" : "text-muted-foreground"
          )}
        >
          <span className="truncate">{attachment.fileName}</span>
          <span className="shrink-0">
            {formatAttachmentSize(attachment.sizeBytes)}
          </span>
        </div>
        {captionElement}
      </div>
    );
  }

  return (
    <div className="min-w-56">
      <a
        href={attachment.url}
        target="_blank"
        rel="noreferrer"
        download={attachment.fileName}
        className={cn(
          "flex items-center gap-3 rounded-xl border p-3 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
          isOwn
            ? "border-white/25 bg-black/10 hover:bg-black/20"
            : "border-border bg-background/70 hover:bg-muted"
        )}
        title={`Tải xuống ${attachment.fileName}`}
      >
        <div
          className={cn(
            "flex size-10 shrink-0 items-center justify-center rounded-lg",
            isOwn ? "bg-white/15 text-white" : "bg-primary/10 text-primary"
          )}
        >
          <FileText className="size-5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium">{attachment.fileName}</p>
          <p
            className={cn(
              "text-xs",
              isOwn ? "text-white/70" : "text-muted-foreground"
            )}
          >
            {formatAttachmentSize(attachment.sizeBytes)}
          </p>
        </div>
        <Download className="size-4 shrink-0" />
      </a>
      {captionElement}
    </div>
  );
}

function ReplyQuote({
  replyTo,
  conversation,
  isOwn,
  onJumpToMessage,
}: {
  replyTo: MessageReplyReference;
  conversation: Conversation;
  isOwn: boolean;
  onJumpToMessage: (messageId: string) => void | Promise<void>;
}) {
  const user = useAuthStore((state) => state.user);

  return (
    <button
      type="button"
      onClick={() => void onJumpToMessage(replyTo.messageId)}
      title="Đi tới tin nhắn gốc"
      className={cn(
        "mb-2 block max-w-full rounded-md border-l-2 px-2 py-1.5 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        isOwn
          ? "border-white/80 bg-black/10 text-white hover:bg-black/20"
          : "border-primary bg-primary/10 text-foreground hover:bg-primary/15"
      )}
    >
      <p className="truncate text-xs font-semibold">
        {replySenderName(replyTo, conversation, user?._id)}
      </p>
      <p
        className={cn(
          "truncate text-xs",
          isOwn ? "text-white/80" : "text-muted-foreground",
          replyTo.isRecalled && "italic"
        )}
      >
        {replyPreview(replyTo)}
      </p>
    </button>
  );
}

interface GroupedReaction {
  emoji: string;
  count: number;
  userIds: string[];
}

function groupReactions(reactions: MessageReaction[] = []): GroupedReaction[] {
  const groups = new Map<string, GroupedReaction>();

  reactions.forEach((reaction) => {
    const current = groups.get(reaction.emoji);
    if (current) {
      current.count += 1;
      current.userIds.push(reaction.userId);
      return;
    }

    groups.set(reaction.emoji, {
      emoji: reaction.emoji,
      count: 1,
      userIds: [reaction.userId],
    });
  });

  return [...groups.values()];
}

function MessageReactions({
  message,
  conversation,
}: {
  message: Message;
  conversation: Conversation;
}) {
  const user = useAuthStore((state) => state.user);
  const setReaction = useChatStore((state) => state.setReaction);
  const removeReaction = useChatStore((state) => state.removeReaction);
  const [updating, setUpdating] = useState(false);
  const reactions = groupReactions(message.reactions);

  if (message.isRecalled || reactions.length === 0) return null;

  const handleReactionClick = async (reaction: GroupedReaction) => {
    if (!user || updating) return;
    setUpdating(true);

    try {
      if (reaction.userIds.includes(user._id)) {
        await removeReaction(message._id);
      } else {
        await setReaction(message._id, reaction.emoji);
      }
    } catch (error) {
      console.error("Không thể cập nhật cảm xúc", error);
      toast.error("Không thể cập nhật cảm xúc. Vui lòng thử lại.");
    } finally {
      setUpdating(false);
    }
  };

  return (
    <div
      className={cn(
        "flex max-w-full flex-wrap gap-1",
        message.isOwn ? "justify-end" : "justify-start"
      )}
    >
      {reactions.map((reaction) => {
        const selected = Boolean(user && reaction.userIds.includes(user._id));
        const names = reaction.userIds.map((userId) => {
          if (userId === user?._id) {
            return `${user.displayName || "Bạn"} (Bạn)`;
          }
          return (
            conversation.participants.find(
              (participant) => participant._id === userId
            )?.displayName ?? "Người dùng FlowChat"
          );
        });

        return (
          <Popover key={reaction.emoji}>
            <PopoverTrigger asChild>
              <button
                type="button"
                title={names.join(", ")}
                className={cn(
                  "flex h-6 items-center gap-1 rounded-full border bg-background px-2 text-xs shadow-sm transition-colors hover:bg-muted",
                  selected && "border-primary bg-primary/10 text-primary"
                )}
              >
                <span aria-hidden="true">{reaction.emoji}</span>
                <span>{reaction.count}</span>
              </button>
            </PopoverTrigger>
            <PopoverContent className="w-64 space-y-3 p-3" side="top">
              <div>
                <p className="text-sm font-semibold">
                  {reaction.emoji} {reaction.count} người
                </p>
                <div className="mt-2 max-h-36 space-y-1 overflow-y-auto text-sm text-muted-foreground">
                  {names.map((name, index) => (
                    <p key={`${reaction.userIds[index]}-${index}`} className="truncate">
                      {name}
                    </p>
                  ))}
                </div>
              </div>
              <Button
                type="button"
                size="sm"
                variant={selected ? "outline" : "default"}
                className="w-full"
                disabled={updating}
                onClick={() => void handleReactionClick(reaction)}
              >
                {selected ? "Gỡ cảm xúc của bạn" : `Thả ${reaction.emoji}`}
              </Button>
            </PopoverContent>
          </Popover>
        );
      })}
    </div>
  );
}

function MessageActions({
  message,
  onForward,
}: {
  message: Message;
  onForward: () => void;
}) {
  const user = useAuthStore((state) => state.user);
  const setReplyingTo = useChatStore((state) => state.setReplyingTo);
  const recallMessage = useChatStore((state) => state.recallMessage);
  const setReaction = useChatStore((state) => state.setReaction);
  const removeReaction = useChatStore((state) => state.removeReaction);
  const updateMessagePin = useChatStore((state) => state.updateMessagePin);
  const [reactionOpen, setReactionOpen] = useState(false);
  const [updatingReaction, setUpdatingReaction] = useState(false);
  const [recalling, setRecalling] = useState(false);
  const [updatingPin, setUpdatingPin] = useState(false);
  const isCallMessage = message.messageType === "call" || Boolean(message.call);
  const isRecalled = Boolean(message.isRecalled);
  const currentReaction = message.reactions?.find(
    (reaction) => reaction.userId === user?._id
  );
  const canOpenMore = !isCallMessage && !isRecalled;
  const canReplyOrReact = !isRecalled;
  const canChangePin = !message.pinnedAt || message.pinnedBy === user?._id;

  const handleRecall = async () => {
    if (recalling || !message.isOwn) return;
    if (!window.confirm("Bạn có chắc muốn thu hồi tin nhắn này?")) return;

    setRecalling(true);
    try {
      await recallMessage(message._id);
      toast.success("Đã thu hồi tin nhắn.");
    } catch (error) {
      console.error("Không thể thu hồi tin nhắn", error);
      toast.error("Không thể thu hồi tin nhắn. Vui lòng thử lại.");
    } finally {
      setRecalling(false);
    }
  };

  const handleReaction = async (emoji: string) => {
    if (updatingReaction) return;
    setUpdatingReaction(true);

    try {
      if (currentReaction?.emoji === emoji) {
        await removeReaction(message._id);
      } else {
        await setReaction(message._id, emoji);
      }
      setReactionOpen(false);
    } catch (error) {
      console.error("Không thể thả cảm xúc", error);
      toast.error("Không thể thả cảm xúc. Vui lòng thử lại.");
    } finally {
      setUpdatingReaction(false);
    }
  };

  const handlePin = async () => {
    if (updatingPin) return;
    setUpdatingPin(true);
    try {
      await updateMessagePin(
        message.conversationId,
        message._id,
        !message.pinnedAt
      );
      toast.success(message.pinnedAt ? "Đã bỏ ghim tin nhắn." : "Đã ghim tin nhắn.");
    } catch (error) {
      console.error("Không thể cập nhật ghim tin nhắn", error);
      toast.error("Không thể cập nhật ghim tin nhắn.");
    } finally {
      setUpdatingPin(false);
    }
  };

  if (!canOpenMore && !canReplyOrReact) return null;

  return (
    <div className="flex shrink-0 items-center gap-0.5 opacity-100 transition-opacity sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100">
      {canOpenMore && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="size-7 rounded-full text-muted-foreground"
              title="Hành động khác"
              aria-label="Hành động khác"
            >
              <EllipsisVertical className="size-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            align={message.isOwn ? "end" : "start"}
            side="top"
          >
            {message.isOwn && (
              <DropdownMenuItem
                variant="destructive"
                disabled={recalling}
                onSelect={() => void handleRecall()}
              >
                <Undo2 />
                Thu hồi
              </DropdownMenuItem>
            )}
            <DropdownMenuItem onSelect={onForward}>
              <Forward />
              Chuyển tiếp
            </DropdownMenuItem>
            <DropdownMenuItem
              disabled={updatingPin || !canChangePin}
              onSelect={() => void handlePin()}
            >
              {message.pinnedAt && canChangePin ? <PinOff /> : <Pin />}
              {message.pinnedAt
                ? canChangePin
                  ? "Bỏ ghim"
                  : "Đã được người khác ghim"
                : "Ghim tin nhắn"}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      )}

      {canReplyOrReact && (
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="size-7 rounded-full text-muted-foreground"
          title="Trả lời tin nhắn"
          aria-label="Trả lời tin nhắn"
          onClick={() => setReplyingTo(message)}
        >
          <Reply className="size-4" />
        </Button>
      )}

      {canReplyOrReact && (
        <Popover open={reactionOpen} onOpenChange={setReactionOpen}>
          <PopoverTrigger asChild>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="size-7 rounded-full text-muted-foreground"
              title="Thả cảm xúc"
              aria-label="Thả cảm xúc"
            >
              <Smile className="size-4" />
            </Button>
          </PopoverTrigger>
          <PopoverContent
            side="top"
            align={message.isOwn ? "end" : "start"}
            className="flex w-auto gap-1 rounded-full p-1.5"
          >
            {quickReactions.map((emoji) => (
              <button
                key={emoji}
                type="button"
                disabled={updatingReaction}
                onClick={() => void handleReaction(emoji)}
                className={cn(
                  "flex size-9 items-center justify-center rounded-full text-xl transition-transform hover:scale-125 hover:bg-muted disabled:opacity-50",
                  currentReaction?.emoji === emoji && "bg-primary/15"
                )}
                aria-label={`Thả cảm xúc ${emoji}`}
              >
                {emoji}
              </button>
            ))}
          </PopoverContent>
        </Popover>
      )}
    </div>
  );
}

const MessageItem = ({
  message,
  index,
  messages,
  selectedConvo,
  lastMessageStatus,
  highlighted = false,
  onJumpToMessage,
}: MessageItemProps) => {
  const [forwardOpen, setForwardOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const prev = index + 1 < messages.length ? messages[index + 1] : undefined;

  const isShowTime =
    index === 0 ||
    new Date(message.createdAt).getTime() -
      new Date(prev?.createdAt || 0).getTime() >
      300000; // 5 phút

  const isGroupBreak = isShowTime || message.senderId !== prev?.senderId;

  if (message.messageType === "system") {
    return (
      <>
        {isShowTime && (
          <span className="flex justify-center px-1 text-xs text-muted-foreground">
            {formatMessageTime(new Date(message.createdAt))}
          </span>
        )}
        <div
          id={`message-${message._id}`}
          data-message-id={message._id}
          className="flex justify-center py-1"
        >
          <span className="max-w-[85%] rounded-full bg-muted px-3 py-1.5 text-center text-xs text-muted-foreground">
            {message.content}
          </span>
        </div>
      </>
    );
  }

  const participant = selectedConvo.participants.find(
    (p: Participant) => p._id.toString() === message.senderId.toString()
  );
  const isCallMessage = message.messageType === "call" || Boolean(message.call);
  const isAttachmentMessage =
    message.messageType === "attachment" || Boolean(message.attachment);
  const isRecalled = Boolean(message.isRecalled);

  return (
    <>
      {/* time */}
      {isShowTime && (
        <span className="flex justify-center text-xs text-muted-foreground px-1">
          {formatMessageTime(new Date(message.createdAt))}
        </span>
      )}

      <div
        id={`message-${message._id}`}
        data-message-id={message._id}
        className={cn(
          "group flex gap-2 message-bounce mt-1 rounded-xl transition-[background-color,box-shadow] duration-300",
          highlighted && "bg-primary/15 ring-2 ring-primary/45 ring-offset-2",
          message.isOwn ? "justify-end" : "justify-start"
        )}
      >
        {/* avatar */}
        {!message.isOwn && (
          <div className="w-8">
            {isGroupBreak && (
              <button
                type="button"
                className="rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                title={`Xem thông tin ${participant?.displayName ?? "người dùng"}`}
                onClick={() => participant && setProfileOpen(true)}
              >
                <UserAvatar
                  type="chat"
                  name={participant?.displayName ?? "FlowChat"}
                  avatarUrl={participant?.avatarUrl ?? undefined}
                />
              </button>
            )}
          </div>
        )}

        <div
          className={cn(
            "flex min-w-0 items-center gap-1",
            message.isOwn ? "flex-row" : "flex-row-reverse"
          )}
        >
          <MessageActions
            message={message}
            onForward={() => setForwardOpen(true)}
          />

          {/* tin nhắn */}
          <div
            className={cn(
              "flex max-w-xs flex-col space-y-1 lg:max-w-md",
              message.isOwn ? "items-end" : "items-start"
            )}
          >
            <Card
              className={cn(
                "max-w-full p-3",
                isRecalled
                  ? "border-border bg-muted/70 text-muted-foreground shadow-none"
                  : isCallMessage
                    ? "border-primary/20 bg-card text-card-foreground shadow-sm"
                    : message.isOwn
                      ? "chat-bubble-sent border-0"
                      : "chat-bubble-received"
              )}
            >
              {isRecalled ? (
                <p className="flex items-center gap-2 text-sm italic">
                  <CircleSlash2 className="size-4 shrink-0" />
                  Tin nhắn đã được thu hồi
                </p>
              ) : (
                <>
                  {message.forwardedFrom && (
                    <p
                      className={cn(
                        "mb-1.5 flex items-center gap-1 text-xs italic",
                        message.isOwn
                          ? "text-white/75"
                          : "text-muted-foreground"
                      )}
                    >
                      <Forward className="size-3" />
                      Đã chuyển tiếp
                    </p>
                  )}

                  {message.pinnedAt && (
                    <p
                      className={cn(
                        "mb-1.5 flex items-center gap-1 text-xs font-medium",
                        message.isOwn ? "text-white/80" : "text-primary"
                      )}
                    >
                      <Pin className="size-3" />
                      Đã ghim
                    </p>
                  )}

                  {message.replyTo && (
                    <ReplyQuote
                      replyTo={message.replyTo}
                      conversation={selectedConvo}
                      isOwn={Boolean(message.isOwn)}
                      onJumpToMessage={onJumpToMessage}
                    />
                  )}

                  {isCallMessage ? (
                    <CallMessageCard
                      message={message}
                      selectedConvo={selectedConvo}
                    />
                  ) : isAttachmentMessage && message.attachment ? (
                    <AttachmentContent
                      attachment={message.attachment}
                      caption={message.content}
                      isOwn={Boolean(message.isOwn)}
                    />
                  ) : (
                    <p className="break-words text-sm leading-relaxed">
                      {message.content}
                    </p>
                  )}
                </>
              )}
            </Card>

            <MessageReactions
              message={message}
              conversation={selectedConvo}
            />

            {/* seen/ delivered */}
            {message.isOwn && message._id === selectedConvo.lastMessage?._id && (
              <Badge
                variant="outline"
                className={cn(
                  "h-4 border-0 px-1.5 py-0.5 text-xs",
                  lastMessageStatus === "seen"
                    ? "bg-primary/20 text-primary"
                    : "bg-muted text-muted-foreground"
                )}
              >
                {lastMessageStatus}
              </Badge>
            )}
          </div>
        </div>
      </div>

      {!isCallMessage && !isRecalled && (
        <ForwardMessageDialog
          message={message}
          open={forwardOpen}
          onOpenChange={setForwardOpen}
        />
      )}
      <UserQuickProfileDialog
        participant={participant ?? null}
        open={profileOpen}
        onOpenChange={setProfileOpen}
      />
    </>
  );
};

export default MessageItem;
