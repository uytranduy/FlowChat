import { useEffect, useMemo, useRef, useState } from "react";
import {
  FileText,
  Images,
  LoaderCircle,
  MoreHorizontal,
  Paperclip,
  Pin,
  PinOff,
  Reply,
  Search,
  Send,
  Undo2,
  X,
  ZoomIn,
  ZoomOut,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import ConversationAttachmentsDialog from "@/components/chat/ConversationAttachmentsDialog";
import MessageFinderDialog from "@/components/chat/MessageFinderDialog";
import { chatService } from "@/services/chatService";
import { useChatStore } from "@/stores/useChatStore";
import type { Message } from "@/types/chat";

const EMPTY_MESSAGES: Message[] = [];
const EMOJIS = ["👍", "❤️", "😂", "😮", "😢", "😡"];

interface InCallChatPanelProps {
  conversationId: string;
  currentUserId?: string;
  mode: "direct" | "group";
  recipientId?: string;
  senderName: (userId: string) => string | undefined;
  onClose: () => void;
  className?: string;
}

function mergeMessages(...groups: Message[][]): Message[] {
  const byId = new Map<string, Message>();
  groups.flat().forEach((message) => byId.set(message._id, message));
  return [...byId.values()].sort(
    (left, right) =>
      new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime()
  );
}

function messagePreview(message: Message): string {
  if (message.isRecalled) return "Tin nhắn đã thu hồi";
  if (message.messageType === "call") return "📞 Lịch sử cuộc gọi";
  if (message.attachment) {
    return message.content?.trim() || message.attachment.fileName;
  }
  return message.content?.trim() || "Tin nhắn";
}

export default function InCallChatPanel({
  conversationId,
  currentUserId,
  mode,
  recipientId,
  senderName,
  onClose,
  className = "",
}: InCallChatPanelProps) {
  const [text, setText] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [sending, setSending] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [replyingTo, setReplyingTo] = useState<Message | null>(null);
  const [contextMessages, setContextMessages] = useState<Message[]>([]);
  const [finderMode, setFinderMode] = useState<"search" | "pinned" | null>(null);
  const [attachmentsOpen, setAttachmentsOpen] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const messages = useChatStore(
    (state) => state.messages[conversationId]?.items ?? EMPTY_MESSAGES
  );
  const conversation = useChatStore((state) =>
    state.conversations.find((item) => item._id === conversationId)
  );
  const refreshMessages = useChatStore((state) => state.refreshLatestMessages);
  const updateMessage = useChatStore((state) => state.updateMessage);
  const displayedMessages = useMemo(() => {
    const merged = mergeMessages(messages, contextMessages);
    return contextMessages.length ? merged : merged.slice(-40);
  }, [contextMessages, messages]);

  useEffect(() => {
    void refreshMessages(conversationId);
    const timer = window.setInterval(
      () => void refreshMessages(conversationId),
      4_000
    );
    return () => window.clearInterval(timer);
  }, [conversationId, refreshMessages]);

  const jumpToMessage = async (message: Message) => {
    let target = document.getElementById(`in-call-message-${message._id}`);
    if (!target) {
      try {
        const around = await chatService.fetchMessagesAround(
          conversationId,
          message._id
        );
        setContextMessages(around);
        await new Promise((resolve) => window.setTimeout(resolve, 80));
        target = document.getElementById(`in-call-message-${message._id}`);
      } catch {
        toast.error("Không thể tải tin nhắn gốc.");
      }
    }
    target?.scrollIntoView({ behavior: "smooth", block: "center" });
    target?.classList.add("ring-2", "ring-amber-400");
    if (target) window.setTimeout(() => target?.classList.remove("ring-2", "ring-amber-400"), 1800);
  };

  const submit = async () => {
    const content = text.trim();
    if ((!content && !file) || sending) return;
    if (mode === "direct" && !recipientId) return toast.error("Không xác định được người nhận.");
    setSending(true);
    try {
      const sent = mode === "group"
        ? await chatService.sendGroupMessage(conversationId, content, file ?? undefined, replyingTo?._id)
        : await chatService.sendDirectMessage(recipientId!, content, file ?? undefined, conversationId, replyingTo?._id);
      updateMessage(sent);
      setText("");
      setFile(null);
      setReplyingTo(null);
      if (fileInput.current) fileInput.current.value = "";
      await refreshMessages(conversationId);
      window.setTimeout(() => listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: "smooth" }), 30);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Không thể gửi tin nhắn.");
    } finally {
      setSending(false);
    }
  };

  const recall = async (message: Message) => {
    if (!window.confirm("Thu hồi tin nhắn này?")) return;
    try {
      updateMessage(await chatService.recallMessage(message._id));
      setSelectedId(null);
    } catch { toast.error("Không thể thu hồi tin nhắn."); }
  };

  const togglePin = async (message: Message) => {
    if (message.pinnedAt && message.pinnedBy !== currentUserId) {
      return toast.error("Chỉ người đã ghim mới có thể bỏ ghim.");
    }
    try {
      updateMessage(await chatService.updateMessagePin(conversationId, message._id, !message.pinnedAt));
      setSelectedId(null);
    } catch { toast.error("Không thể cập nhật ghim tin nhắn."); }
  };

  const react = async (message: Message, emoji: string) => {
    try {
      const mine = message.reactions?.find((reaction) => reaction.userId === currentUserId);
      updateMessage(mine?.emoji === emoji
        ? await chatService.removeReaction(message._id)
        : await chatService.setReaction(message._id, emoji));
      setSelectedId(null);
    } catch { toast.error("Không thể cập nhật cảm xúc."); }
  };

  return (
    <aside className={`flex min-h-0 flex-col overflow-hidden rounded-2xl border border-white/10 bg-slate-950/95 text-white shadow-2xl ${className}`}>
      <div className="flex items-center justify-between border-b border-white/10 px-3 py-2">
        <div><p className="font-semibold">Chat trong cuộc gọi</p><p className="text-xs text-slate-400">Đầy đủ tính năng của cuộc trò chuyện</p></div>
        <div className="flex items-center">
          <Button size="icon" variant="ghost" title="Tìm kiếm tin nhắn" onClick={() => setFinderMode("search")}><Search /></Button>
          <Button size="icon" variant="ghost" title="Tin nhắn đã ghim" onClick={() => setFinderMode("pinned")}><Pin /></Button>
          <Button size="icon" variant="ghost" title="Ảnh, video và tệp" onClick={() => setAttachmentsOpen(true)}><Images /></Button>
          <Button size="icon" variant="ghost" onClick={onClose} title="Đóng chat"><X /></Button>
        </div>
      </div>

      <div ref={listRef} className="flex-1 space-y-2 overflow-y-auto p-3">
        {displayedMessages.length === 0 && <p className="py-8 text-center text-sm text-slate-400">Chưa có tin nhắn.</p>}
        {displayedMessages.map((message) => (
          <CallChatMessage
            key={message._id}
            message={message}
            own={message.senderId === currentUserId}
            currentUserId={currentUserId}
            senderName={senderName(message.senderId)}
            selected={selectedId === message._id}
            onSelect={() => setSelectedId((value) => value === message._id ? null : message._id)}
            onReply={() => { setReplyingTo(message); setSelectedId(null); }}
            onRecall={() => void recall(message)}
            onPin={() => void togglePin(message)}
            onReact={(emoji) => void react(message, emoji)}
            onJumpReply={() => message.replyTo && void jumpToMessage({ _id: message.replyTo.messageId } as Message)}
          />
        ))}
      </div>

      {replyingTo && (
        <div className="mx-3 mb-2 flex items-center gap-2 rounded-xl border-l-2 border-violet-400 bg-white/10 px-3 py-2 text-xs">
          <Reply className="size-4" /><span className="min-w-0 flex-1 truncate">Trả lời: {messagePreview(replyingTo)}</span>
          <button type="button" onClick={() => setReplyingTo(null)}><X className="size-4" /></button>
        </div>
      )}
      {file && <div className="mx-3 mb-2 flex items-center gap-2 rounded-xl bg-white/10 px-3 py-2 text-xs"><FileText className="size-4"/><span className="min-w-0 flex-1 truncate">{file.name}</span><button type="button" onClick={() => setFile(null)}><X className="size-4"/></button></div>}
      <div className="flex gap-2 border-t border-white/10 p-3">
        <input ref={fileInput} type="file" className="hidden" onChange={(event) => setFile(event.target.files?.[0] ?? null)} />
        <Button type="button" size="icon" variant="secondary" disabled={sending} title="Gửi ảnh, video hoặc tệp" onClick={() => fileInput.current?.click()}><Paperclip /></Button>
        <input value={text} onChange={(event) => setText(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); void submit(); } }} placeholder="Nhắn tin..." className="min-w-0 flex-1 rounded-xl border border-white/10 bg-slate-900 px-3 py-2 text-sm outline-none focus:border-violet-400" />
        <Button size="icon" disabled={(!text.trim() && !file) || sending} onClick={() => void submit()}>{sending ? <LoaderCircle className="animate-spin" /> : <Send />}</Button>
      </div>

      {conversation && <MessageFinderDialog conversation={conversation} mode={finderMode ?? "search"} open={finderMode !== null} onOpenChange={(open) => !open && setFinderMode(null)} onSelectMessage={jumpToMessage} />}
      <ConversationAttachmentsDialog conversationId={conversationId} open={attachmentsOpen} onOpenChange={setAttachmentsOpen} />
    </aside>
  );
}

function CallChatMessage({ message, own, currentUserId, senderName, selected, onSelect, onReply, onRecall, onPin, onReact, onJumpReply }: {
  message: Message; own: boolean; currentUserId?: string; senderName?: string; selected: boolean;
  onSelect: () => void; onReply: () => void; onRecall: () => void; onPin: () => void;
  onReact: (emoji: string) => void; onJumpReply: () => void;
}) {
  const [imageOpen, setImageOpen] = useState(false);
  const [zoom, setZoom] = useState(1);
  const attachment = message.attachment;
  const reactions = useMemo(() => {
    const grouped = new Map<string, number>();
    message.reactions?.forEach((reaction) => grouped.set(reaction.emoji, (grouped.get(reaction.emoji) ?? 0) + 1));
    return [...grouped.entries()];
  }, [message.reactions]);

  return (
    <div id={`in-call-message-${message._id}`} className={`rounded-xl transition ${own ? "ml-auto" : "mr-auto"}`}>
      {selected && !message.isRecalled && (
        <div className={`mb-1 flex flex-wrap gap-1 ${own ? "justify-end" : "justify-start"}`}>
          <Button size="icon" variant="secondary" className="size-7" title="Trả lời" onClick={onReply}><Reply /></Button>
          <div className="flex rounded-md bg-slate-800 p-0.5">{EMOJIS.map((emoji) => <button key={emoji} type="button" className="px-1 text-base" onClick={() => onReact(emoji)}>{emoji}</button>)}</div>
          <Button size="icon" variant="secondary" className="size-7" title={message.pinnedAt ? "Bỏ ghim" : "Ghim"} onClick={onPin}>{message.pinnedAt ? <PinOff /> : <Pin />}</Button>
          {own && message.messageType !== "call" && <Button size="icon" variant="secondary" className="size-7" title="Thu hồi" onClick={onRecall}><Undo2 /></Button>}
          <MoreHorizontal className="size-5 self-center text-slate-400" />
        </div>
      )}
      <div role="button" tabIndex={0} className={`block max-w-[90%] overflow-hidden rounded-2xl px-3 py-2 text-left text-sm ${own ? "ml-auto bg-violet-600" : "bg-slate-800"}`} onClick={onSelect} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") onSelect(); }}>
        {!own && <p className="mb-0.5 text-[11px] font-semibold text-violet-300">{senderName || "Thành viên"}</p>}
        {message.pinnedAt && <p className="mb-1 flex items-center gap-1 text-[11px]"><Pin className="size-3"/>Đã ghim</p>}
        {message.replyTo && <span role="button" tabIndex={0} className="mb-1 block rounded-lg border-l-2 border-violet-300 bg-black/20 px-2 py-1 text-xs" onClick={(event) => { event.stopPropagation(); onJumpReply(); }} onKeyDown={(event) => { if (event.key === "Enter") onJumpReply(); }}>{message.replyTo.content || "Tin nhắn gốc"}</span>}
        {attachment?.kind === "image" && <><span role="button" tabIndex={0} className="mb-1 block cursor-zoom-in overflow-hidden rounded-lg" onClick={(event) => { event.stopPropagation(); setZoom(1); setImageOpen(true); }}><img src={attachment.url} alt={attachment.fileName} className="max-h-44 w-full object-contain" /></span><Dialog open={imageOpen} onOpenChange={setImageOpen}><DialogContent className="h-[94vh] w-[96vw] max-w-none overflow-hidden border-0 bg-black/95 p-0 text-white"><DialogTitle className="sr-only">{attachment.fileName}</DialogTitle><div className="absolute left-1/2 top-4 z-20 flex -translate-x-1/2 gap-2 rounded-full bg-black/65 p-1"><Button size="icon" variant="ghost" onClick={() => setZoom((v) => Math.max(.5, v-.25))}><ZoomOut/></Button><Button size="icon" variant="ghost" onClick={() => setZoom((v) => Math.min(3, v+.25))}><ZoomIn/></Button></div><div className="flex h-full items-center justify-center overflow-auto p-10"><img src={attachment.url} alt={attachment.fileName} className="max-h-full max-w-full object-contain" style={{transform:`scale(${zoom})`}}/></div></DialogContent></Dialog></>}
        {attachment?.kind === "video" && <video src={attachment.url} controls playsInline className="mb-1 max-h-44 w-full rounded-lg bg-black" onClick={(event) => event.stopPropagation()} />}
        {attachment?.kind === "file" && <a href={attachment.url} target="_blank" rel="noreferrer" className="mb-1 flex items-center gap-2 underline" onClick={(event) => event.stopPropagation()}><FileText className="size-4"/><span className="truncate">{attachment.fileName}</span></a>}
        <p className={message.isRecalled ? "italic text-slate-400" : "break-words"}>{messagePreview(message)}</p>
      </div>
      {reactions.length > 0 && <div className={`mt-1 flex gap-1 ${own ? "justify-end" : "justify-start"}`}>{reactions.map(([emoji, count]) => <button key={emoji} type="button" className={`rounded-full border px-2 py-0.5 text-xs ${message.reactions?.some((r) => r.userId === currentUserId && r.emoji === emoji) ? "border-violet-400 bg-violet-500/30" : "border-white/15 bg-slate-800"}`} onClick={() => onReact(emoji)}>{emoji} {count}</button>)}</div>}
    </div>
  );
}
