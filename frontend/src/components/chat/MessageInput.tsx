import { useAuthStore } from "@/stores/useAuthStore";
import type { Conversation } from "@/types/chat";
import { useEffect, useRef, useState } from "react";
import { Button } from "../ui/button";
import {
  FileText,
  Image as ImageIcon,
  Loader2,
  Paperclip,
  Reply,
  Send,
  Video,
  X,
} from "lucide-react";
import { Input } from "../ui/input";
import EmojiPicker from "./EmojiPicker";
import { useChatStore } from "@/stores/useChatStore";
import { toast } from "sonner";
import type { FriendRelationship } from "@/types/user";

const MEBIBYTE = 1024 * 1024;

function fileKind(file: File): "image" | "video" | "file" {
  if (file.type.startsWith("image/")) return "image";
  if (file.type.startsWith("video/")) return "video";
  return "file";
}

function maxFileSize(file: File): number {
  switch (fileKind(file)) {
    case "image":
      return 10 * MEBIBYTE;
    case "video":
      return 50 * MEBIBYTE;
    default:
      return 20 * MEBIBYTE;
  }
}

function formatFileSize(size: number): string {
  if (size < 1024) return `${size} B`;
  if (size < MEBIBYTE) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / MEBIBYTE).toFixed(1)} MB`;
}

const MessageInput = ({ selectedConvo, relationship, onRelationshipChanged }: { selectedConvo: Conversation; relationship?: FriendRelationship | null; onRelationshipChanged?: () => Promise<void> }) => {
  const { user } = useAuthStore();
  const {
    sendDirectMessage,
    sendGroupMessage,
    replyingTo,
    setReplyingTo,
  } = useChatStore();
  const [value, setValue] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const interactionEnabled =
    selectedConvo.type !== "direct" || relationship?.canSendMessage === true;

  useEffect(() => {
    if (!selectedFile || fileKind(selectedFile) === "file") {
      setPreviewUrl(null);
      return;
    }

    const url = URL.createObjectURL(selectedFile);
    setPreviewUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [selectedFile]);

  useEffect(() => {
    setSelectedFile(null);
    setPreviewUrl(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  }, [selectedConvo._id]);

  if (!user) return null;

  const replySender = replyingTo
    ? replyingTo.senderId === user._id
      ? "Bạn"
      : (selectedConvo.participants.find(
          (participant) => participant._id === replyingTo.senderId
        )?.displayName ?? "Thành viên")
    : null;
  const replyPreview = replyingTo?.isRecalled
    ? "Tin nhắn đã được thu hồi"
    : replyingTo?.messageType === "call"
      ? "Cuộc gọi"
      : replyingTo?.messageType === "attachment"
        ? replyingTo.attachment?.kind === "image"
          ? "Ảnh"
          : replyingTo.attachment?.kind === "video"
            ? "Video"
            : replyingTo.attachment?.fileName || "Tệp đính kèm"
      : replyingTo?.content?.trim() || "Tin nhắn";

  const sendMessage = async () => {
    if ((!value.trim() && !selectedFile) || sending || !interactionEnabled) return;
    const currValue = value;
    const currFile = selectedFile ?? undefined;
    const replyToMessageId = replyingTo?._id;
    setSending(true);

    try {
      if (selectedConvo.type === "direct") {
        const participants = selectedConvo.participants;
        const otherUser = participants.filter((p) => p._id !== user._id)[0];
        await sendDirectMessage(
          otherUser._id,
          currValue,
          currFile,
          replyToMessageId
        );
      } else {
        await sendGroupMessage(
          selectedConvo._id,
          currValue,
          currFile,
          replyToMessageId
        );
      }
      setValue("");
      setSelectedFile(null);
      if (fileInputRef.current) fileInputRef.current.value = "";
      setReplyingTo(null);
      await onRelationshipChanged?.();
    } catch (error) {
      console.error(error);
      const message = (
        error as { response?: { data?: { message?: string } } }
      ).response?.data?.message;
      toast.error(message || "Lỗi xảy ra khi gửi tin nhắn. Bạn hãy thử lại!");
    } finally {
      setSending(false);
    }
  };

  const handleFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const limit = maxFileSize(file);
    if (file.size > limit) {
      const kind = fileKind(file);
      toast.error(
        `${kind === "image" ? "Ảnh" : kind === "video" ? "Video" : "Tệp"} không được vượt quá ${formatFileSize(limit)}.`
      );
      event.target.value = "";
      return;
    }

    setSelectedFile(file);
  };

  const removeSelectedFile = () => {
    setSelectedFile(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") {
      e.preventDefault();
      sendMessage();
    }
  };

  return (
    <div className="bg-background p-3">
      {selectedConvo.type === "direct" && relationship?.request?.direction === "incoming" && (
        <p className="mb-2 text-center text-sm text-muted-foreground">Hãy chấp nhận lời mời nhắn tin trước khi trả lời.</p>
      )}
      {replyingTo && (
        <div className="mb-2 flex items-center gap-2 rounded-lg border border-primary/20 bg-primary/5 px-3 py-2">
          <Reply className="size-4 shrink-0 text-primary" />
          <div className="min-w-0 flex-1 border-l-2 border-primary pl-2">
            <p className="truncate text-xs font-semibold text-primary">
              Đang trả lời {replySender}
            </p>
            <p className="truncate text-xs text-muted-foreground">
              {replyPreview}
            </p>
          </div>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="size-7 shrink-0 rounded-full"
            onClick={() => setReplyingTo(null)}
            aria-label="Hủy trả lời"
            title="Hủy trả lời"
          >
            <X className="size-4" />
          </Button>
        </div>
      )}

      {selectedFile && (
        <div className="mb-2 flex items-center gap-3 rounded-xl border border-primary/20 bg-primary/5 p-2">
          <div className="flex size-14 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-background text-primary">
            {fileKind(selectedFile) === "image" && previewUrl ? (
              <img
                src={previewUrl}
                alt="Ảnh chuẩn bị gửi"
                className="size-full object-cover"
              />
            ) : fileKind(selectedFile) === "video" && previewUrl ? (
              <video
                src={previewUrl}
                muted
                className="size-full object-cover"
              />
            ) : (
              <FileText className="size-7" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium text-foreground">
              {selectedFile.name}
            </p>
            <p className="flex items-center gap-1 text-xs text-muted-foreground">
              {fileKind(selectedFile) === "image" ? (
                <ImageIcon className="size-3.5" />
              ) : fileKind(selectedFile) === "video" ? (
                <Video className="size-3.5" />
              ) : (
                <FileText className="size-3.5" />
              )}
              {formatFileSize(selectedFile.size)}
            </p>
          </div>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="size-8 shrink-0 rounded-full"
            onClick={removeSelectedFile}
            disabled={sending}
            aria-label="Bỏ tệp đã chọn"
            title="Bỏ tệp đã chọn"
          >
            <X className="size-4" />
          </Button>
        </div>
      )}

      <div className="flex min-h-9 items-center gap-2">
        <input
          ref={fileInputRef}
          type="file"
          accept=".jpg,.jpeg,.png,.gif,.webp,.bmp,.heic,.heif,.mp4,.mpeg,.mpg,.webm,.mov,.avi,.mkv,.m4v,.3gp,.3g2,.pdf,.txt,.csv,.rtf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.odt,.ods,.odp,.zip,.rar,.7z"
          className="sr-only"
          onChange={handleFileChange}
          aria-label="Chọn ảnh, video hoặc tệp"
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="hover:bg-primary/10 transition-smooth"
          onClick={() => fileInputRef.current?.click()}
          disabled={sending || !interactionEnabled}
          title="Gửi ảnh, video hoặc tệp"
          aria-label="Gửi ảnh, video hoặc tệp"
        >
          <Paperclip className="size-4" />
        </Button>

        <div className="relative flex-1">
          <Input
            onKeyDown={handleKeyPress}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            disabled={sending || !interactionEnabled}
            placeholder={
              selectedFile
                ? "Thêm chú thích..."
                : replyingTo
                  ? "Nhập nội dung trả lời..."
                  : "Soạn tin nhắn..."
            }
            className="pr-20 h-9 bg-white border-border/50 focus:border-primary/50 transition-smooth resize-none"
          />
          <div className="absolute right-2 top-1/2 flex -translate-y-1/2 items-center gap-1">
            <Button
              asChild
              variant="ghost"
              size="icon"
              className="size-8 hover:bg-primary/10 transition-smooth"
            >
              <div>
                <EmojiPicker
                  onChange={(emoji: string) => setValue(`${value}${emoji}`)}
                />
              </div>
            </Button>
          </div>
        </div>

        <Button
          type="button"
          onClick={() => void sendMessage()}
          className="bg-gradient-chat hover:shadow-glow transition-smooth hover:scale-105"
          disabled={(!value.trim() && !selectedFile) || sending || !interactionEnabled}
          aria-label={sending ? "Đang gửi" : "Gửi tin nhắn"}
        >
          {sending ? (
            <Loader2 className="size-4 animate-spin text-white" />
          ) : (
            <Send className="size-4 text-white" />
          )}
        </Button>
      </div>
    </div>
  );
};

export default MessageInput;
