import { useEffect, useMemo, useState } from "react";
import {
  Download,
  FileText,
  Images,
  LoaderCircle,
  Play,
  ZoomIn,
  ZoomOut,
} from "lucide-react";
import { toast } from "sonner";

import { chatService } from "@/services/chatService";
import type { Message, MessageAttachment } from "@/types/chat";
import { Button } from "../ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "../ui/dialog";

type AttachmentFilter = "all" | "image" | "video" | "file";

const filters: Array<{ value: AttachmentFilter; label: string }> = [
  { value: "all", label: "Tất cả" },
  { value: "image", label: "Ảnh" },
  { value: "video", label: "Video" },
  { value: "file", label: "Tệp" },
];

function formatSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "Không rõ dung lượng";
  if (bytes < 1024 * 1024) return `${Math.ceil(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export default function ConversationAttachmentsDialog({
  conversationId,
  open,
  onOpenChange,
}: {
  conversationId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [filter, setFilter] = useState<AttachmentFilter>("all");
  const [loading, setLoading] = useState(false);
  const [viewingImage, setViewingImage] = useState<MessageAttachment | null>(null);
  const [zoom, setZoom] = useState(1);

  useEffect(() => {
    if (!open) {
      setMessages([]);
      setFilter("all");
      setViewingImage(null);
      return;
    }
    let cancelled = false;
    setLoading(true);
    void chatService
      .fetchConversationAttachments(conversationId)
      .then((result) => {
        if (!cancelled) setMessages(result);
      })
      .catch((error) => {
        console.error("Không thể tải tệp trong cuộc trò chuyện", error);
        if (!cancelled) toast.error("Không thể tải ảnh và tệp đã gửi.");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [conversationId, open]);

  const filtered = useMemo(
    () =>
      messages.filter(
        (message) =>
          message.attachment &&
          (filter === "all" || message.attachment.kind === filter)
      ),
    [filter, messages]
  );

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="flex max-h-[88vh] flex-col sm:max-w-3xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Images /> Ảnh, video và tệp đã gửi
            </DialogTitle>
            <DialogDescription>
              Tất cả nội dung đính kèm trong cuộc trò chuyện này.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-wrap gap-2">
            {filters.map((item) => (
              <Button
                key={item.value}
                type="button"
                size="sm"
                variant={filter === item.value ? "default" : "outline"}
                onClick={() => setFilter(item.value)}
              >
                {item.label}
              </Button>
            ))}
          </div>
          <div className="min-h-52 flex-1 overflow-y-auto pr-1 beautiful-scrollbar">
            {loading ? (
              <div className="flex h-52 items-center justify-center">
                <LoaderCircle className="animate-spin text-primary" />
              </div>
            ) : filtered.length === 0 ? (
              <div className="flex h-52 flex-col items-center justify-center gap-2 text-muted-foreground">
                <Images />
                Chưa có nội dung phù hợp.
              </div>
            ) : (
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {filtered.map((message) => {
                  const attachment = message.attachment!;
                  if (attachment.kind === "image") {
                    return (
                      <button
                        key={message._id}
                        type="button"
                        className="group relative aspect-square overflow-hidden rounded-xl border bg-muted"
                        title={`Phóng to ${attachment.fileName}`}
                        onClick={() => {
                          setZoom(1);
                          setViewingImage(attachment);
                        }}
                      >
                        <img
                          src={attachment.url}
                          alt={attachment.fileName}
                          loading="lazy"
                          className="h-full w-full object-cover transition-transform group-hover:scale-105"
                        />
                      </button>
                    );
                  }
                  if (attachment.kind === "video") {
                    return (
                      <div key={message._id} className="overflow-hidden rounded-xl border bg-card">
                        <video
                          src={attachment.url}
                          controls
                          playsInline
                          preload="metadata"
                          className="aspect-video w-full bg-black object-contain"
                        />
                        <p className="truncate p-2 text-xs" title={attachment.fileName}>
                          <Play className="mr-1 inline size-3" />
                          {attachment.fileName}
                        </p>
                      </div>
                    );
                  }
                  return (
                    <a
                      key={message._id}
                      href={attachment.url}
                      target="_blank"
                      rel="noreferrer"
                      download={attachment.fileName}
                      className="flex min-h-28 flex-col items-center justify-center gap-2 rounded-xl border bg-card p-3 text-center hover:bg-muted"
                    >
                      <FileText className="size-8 text-primary" />
                      <span className="w-full truncate text-sm font-medium">
                        {attachment.fileName}
                      </span>
                      <span className="text-xs text-muted-foreground">
                        {formatSize(attachment.sizeBytes)}
                      </span>
                      <Download className="size-4" />
                    </a>
                  );
                })}
              </div>
            )}
          </div>
        </DialogContent>
      </Dialog>

      <Dialog
        open={Boolean(viewingImage)}
        onOpenChange={(nextOpen) => !nextOpen && setViewingImage(null)}
      >
        <DialogContent className="h-[94vh] w-[96vw] max-w-none overflow-hidden border-0 bg-black/95 p-0 text-white">
          <DialogTitle className="sr-only">
            {viewingImage?.fileName || "Xem ảnh"}
          </DialogTitle>
          <div className="absolute left-1/2 top-4 z-20 flex -translate-x-1/2 items-center gap-2 rounded-full bg-black/65 p-1">
            <Button type="button" size="icon" variant="ghost" className="text-white" disabled={zoom <= .5} onClick={() => setZoom((value) => Math.max(.5, value - .25))}><ZoomOut /></Button>
            <span className="min-w-14 text-center text-sm">{Math.round(zoom * 100)}%</span>
            <Button type="button" size="icon" variant="ghost" className="text-white" disabled={zoom >= 3} onClick={() => setZoom((value) => Math.min(3, value + .25))}><ZoomIn /></Button>
          </div>
          <div className="flex h-full w-full items-center justify-center overflow-auto p-10">
            {viewingImage && <img src={viewingImage.url} alt={viewingImage.fileName} className="max-h-full max-w-full select-none object-contain" style={{ transform: `scale(${zoom})` }} />}
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
