import type { CallMediaType } from "./call";

export interface Participant {
  _id: string;
  displayName: string;
  username?: string | null;
  avatarUrl?: string | null;
  bio?: string | null;
  lastSeenAt?: string | null;
  presenceVisible?: boolean;
  isOnline?: boolean;
  joinedAt: string;
}

export interface SeenUser {
  _id: string;
  displayName?: string;
  avatarUrl?: string | null;
}

export interface Group {
  name: string;
  createdBy: string;
  allowMembersToInvite?: boolean;
  dissolvedAt?: string | null;
  dissolvedBy?: string | null;
}

export interface LastMessage {
  _id: string;
  content: string | null;
  createdAt: string;
  messageType?: "text" | "call" | "attachment" | "system";
  call?: CallMessageMetadata | null;
  attachment?: Pick<MessageAttachment, "kind" | "fileName"> | null;
  isRecalled?: boolean;
  sender?: {
    _id: string;
    displayName: string;
    avatarUrl?: string | null;
  };
  senderId?:
    | string
    | {
        _id: string;
        displayName?: string;
        avatarUrl?: string | null;
      };
}

export interface MessageReplyReference {
  messageId: string;
  senderId: string;
  content?: string | null;
  messageType: "text" | "call" | "attachment" | "system";
  attachment?: Pick<MessageAttachment, "kind" | "fileName"> | null;
  isRecalled: boolean;
}

export type AttachmentKind = "image" | "video" | "file";

export interface MessageAttachment {
  kind: AttachmentKind;
  url: string;
  publicId: string;
  fileName: string;
  mimeType: string;
  sizeBytes: number;
  resourceType: "image" | "video" | "raw";
  width?: number | null;
  height?: number | null;
  durationSeconds?: number | null;
}

export interface MessageReaction {
  userId: string;
  emoji: string;
  createdAt: string;
}

export interface ForwardedMessageReference {
  messageId: string;
}

export interface CallMessageMetadata {
  callId: string;
  mediaType: CallMediaType;
  callerId: string;
  calleeId: string;
  reason: string;
  durationSeconds: number;
  startedAt: string;
  acceptedAt?: string | null;
  endedAt: string;
}

export interface Conversation {
  _id: string;
  type: "direct" | "group";
  group: Group;
  participants: Participant[];
  lastMessageAt: string;
  seenBy: SeenUser[];
  lastMessage: LastMessage | null;
  unreadCounts: Record<string, number>; // key = userId, value = unread count
  createdAt: string;
  updatedAt: string;
}

export interface ConversationResponse {
  conversations: Conversation[];
}

export interface Message {
  _id: string;
  conversationId: string;
  senderId: string;
  content: string | null;
  messageType: "text" | "call" | "attachment" | "system";
  call?: CallMessageMetadata | null;
  attachment?: MessageAttachment | null;
  imgUrl?: string | null;
  isRecalled?: boolean;
  recalledAt?: string | null;
  replyTo?: MessageReplyReference | null;
  reactions?: MessageReaction[];
  forwardedFrom?: ForwardedMessageReference | null;
  updatedAt?: string | null;
  createdAt: string;
  isOwn?: boolean;
}
