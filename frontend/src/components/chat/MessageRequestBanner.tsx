import { useState } from "react";
import { Ban, Check, Clock3 } from "lucide-react";
import { toast } from "sonner";
import type { FriendRelationship } from "@/types/user";
import type { Participant } from "@/types/chat";
import { friendService } from "@/services/friendService";
import { blockService } from "@/services/blockService";
import { Button } from "../ui/button";

export default function MessageRequestBanner({ relationship, otherUser, onChanged }: { relationship: FriendRelationship | null; otherUser: Participant; onChanged: () => Promise<void> }) {
  const [pending, setPending] = useState(false);
  if (!relationship || (relationship.isFriend && !relationship.blockStatus?.isBlocked)) return null;

  if (relationship.blockStatus?.isBlocked) {
    return (
      <div className="border-t bg-destructive/10 px-4 py-3 text-center text-sm text-destructive">
        {relationship.blockStatus.isBlockedByMe
          ? `Bạn đã chặn ${otherUser.displayName}. Hãy huỷ chặn trong hồ sơ để tiếp tục liên hệ.`
          : `${otherUser.displayName} đã chặn bạn. Hai người không thể nhắn tin hoặc gọi điện.`}
      </div>
    );
  }

  const accept = async () => {
    if (!relationship.request || pending) return;
    setPending(true);
    try {
      await friendService.acceptRequest(relationship.request._id);
      await onChanged();
      toast.success(`Bạn và ${otherUser.displayName} đã trở thành bạn bè.`);
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể chấp nhận lời mời.");
    } finally { setPending(false); }
  };

  const block = async () => {
    if (pending || !window.confirm(`Chặn ${otherUser.displayName}?`)) return;
    setPending(true);
    try {
      await blockService.block(otherUser._id);
      await onChanged();
      toast.success("Đã chặn người dùng.");
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể chặn người dùng.");
    } finally { setPending(false); }
  };

  if (relationship.request?.direction === "incoming") {
    return (
      <div className="border-t bg-muted/70 px-4 py-3">
        <p className="text-center text-sm text-muted-foreground">
          Nếu chấp nhận, bạn và <strong>{otherUser.displayName}</strong> sẽ trở thành bạn bè và có thể nhắn tin, gọi điện cho nhau.
        </p>
        <div className="mt-3 flex justify-center gap-2">
          <Button variant="destructive" disabled={pending} onClick={() => void block()}><Ban /> Chặn</Button>
          <Button disabled={pending} onClick={() => void accept()}><Check /> Chấp nhận</Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex items-center justify-center gap-2 border-t bg-muted/60 px-4 py-2 text-sm text-muted-foreground">
      <Clock3 className="size-4" /> Đang chờ {otherUser.displayName} chấp nhận. Bạn có thể gửi thêm tin nhắn nhưng chưa thể gọi.
    </div>
  );
}
