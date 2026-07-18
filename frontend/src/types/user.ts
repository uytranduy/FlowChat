export interface User {
  _id: string;
  username: string;
  email: string;
  authProvider?: "local" | "google";
  displayName: string;
  avatarUrl?: string;
  bio?: string;
  phone?: string;
  showOnlineStatus?: boolean;
  notificationsEnabled?: boolean;
  isOnline?: boolean;
  lastSeenAt?: string | null;
  presenceVisible?: boolean;
  createdAt?: string;
  updatedAt?: string;
}

export interface Friend {
  _id: string;
  username: string;
  displayName: string;
  avatarUrl?: string;
}

export interface FriendRequest {
  _id: string;
  from?: {
    _id: string;
    username: string;
    displayName: string;
    avatarUrl?: string;
  };
  to?: {
    _id: string;
    username: string;
    displayName: string;
    avatarUrl?: string;
  };
  message: string;
  createdAt: string;
  updatedAt: string;
}

export interface FriendRelationship {
  isFriend: boolean;
  canCall: boolean;
  canSendMessage: boolean;
  blockStatus?: {
    isBlocked: boolean;
    isBlockedByMe: boolean;
    hasBlockedMe: boolean;
  };
  request: {
    _id: string;
    from: string;
    to: string;
    message: string;
    createdAt: string;
    direction: "incoming" | "outgoing";
  } | null;
}
