import type { FriendRequest } from "@/types/user";
import type { ReactNode } from "react";
import UserAvatar from "../chat/UserAvatar";

interface RequestItemProps {
  requestInfo: FriendRequest;
  actions: ReactNode;
  type: "sent" | "received";
}

const FriendRequestItem = ({ requestInfo, actions, type }: RequestItemProps) => {
  if (!requestInfo) {
    return;
  }
  const info = type === "sent" ? requestInfo.to : requestInfo.from;

  if (!info) {
    return;
  }

  const introduction = requestInfo.message?.trim();

  return (
    <div className="flex flex-col gap-3 rounded-lg border border-primary-foreground p-3 shadow-md sm:flex-row sm:items-center sm:justify-between">
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-3">
          <UserAvatar
            type="sidebar"
            name={info.displayName}
          />
          <div className="min-w-0">
            <p className="truncate font-medium">{info.displayName}</p>
            <p className="truncate text-sm text-muted-foreground">@{info.username}</p>
          </div>
        </div>
        {introduction && (
          <div className="mt-3 rounded-lg bg-muted/70 px-3 py-2">
            <p className="text-xs font-medium text-muted-foreground">Lời giới thiệu</p>
            <p className="mt-1 whitespace-pre-wrap break-words text-sm">{introduction}</p>
          </div>
        )}
      </div>
      <div className="shrink-0">{actions}</div>
    </div>
  );
};

export default FriendRequestItem;
