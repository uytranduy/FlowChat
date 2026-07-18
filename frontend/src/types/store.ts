import type { Socket } from "socket.io-client";
import type { Conversation, Message } from "./chat";
import type { Friend, FriendRequest, User } from "./user";

export interface AuthState {
  accessToken: string | null;
  user: User | null;
  loading: boolean;

  setAccessToken: (accessToken: string) => void;
  setUser: (user: User) => void;
  clearState: () => void;
  signUp: (
    username: string,
    password: string,
    email: string,
    firstName: string,
    lastName: string
  ) => Promise<boolean>;
  signIn: (username: string, password: string) => Promise<boolean>;
  signInWithGoogle: (idToken: string) => Promise<boolean>;
  signOut: () => Promise<void>;
  fetchMe: () => Promise<void>;
  refresh: () => Promise<void>;
}

export interface ThemeState {
  isDark: boolean;
  toggleTheme: () => void;
  setTheme: (dark: boolean) => void;
}

export interface ChatState {
  conversations: Conversation[];
  messages: Record<
    string,
    {
      items: Message[];
      hasMore: boolean; // infinite-scroll
      nextCursor?: string | null; // phân trang
    }
  >;
  activeConversationId: string | null;
  replyingTo: Message | null;
  convoLoading: boolean;
  messageLoading: boolean;
  loading: boolean;
  reset: () => void;

  setActiveConversation: (id: string | null) => void;
  setReplyingTo: (message: Message | null) => void;
  fetchConversations: () => Promise<void>;
  fetchMessages: (conversationId?: string) => Promise<void>;
  refreshLatestMessages: (conversationId?: string) => Promise<void>;
  sendDirectMessage: (
    recipientId: string,
    content: string,
    file?: File,
    replyToMessageId?: string
  ) => Promise<void>;
  sendGroupMessage: (
    conversationId: string,
    content: string,
    file?: File,
    replyToMessageId?: string
  ) => Promise<void>;
  // add message
  addMessage: (message: Message) => Promise<void>;
  updateMessage: (message: Message) => void;
  recallMessage: (messageId: string) => Promise<void>;
  setReaction: (messageId: string, emoji: string) => Promise<void>;
  removeReaction: (messageId: string) => Promise<void>;
  forwardMessage: (messageId: string, conversationId: string) => Promise<void>;
  updateMessagePin: (
    conversationId: string,
    messageId: string,
    pinned: boolean
  ) => Promise<void>;
  // update convo
  updateConversation: (conversation: Partial<Conversation> & { _id: string }) => void;
  removeConversation: (conversationId: string) => void;
  clearConversationMessages: (conversationId: string) => void;
  markAsSeen: () => Promise<void>;
  addConvo: (convo: Conversation) => void;
  createConversation: (
    type: "group" | "direct",
    name: string,
    memberIds: string[]
  ) => Promise<Conversation>;
}

export interface SocketState {
  socket: Socket | null;
  isConnected: boolean;
  onlineUsers: string[];
  relationshipRevision: number;
  lastSeenByUser: Record<string, string>;
  connectSocket: () => void;
  disconnectSocket: () => void;
}

export interface FriendState {
  friends: Friend[];
  loading: boolean;
  receivedList: FriendRequest[];
  sentList: FriendRequest[];
  searchByUsername: (username: string) => Promise<User | null>;
  addFriend: (to: string, message?: string) => Promise<string>;
  getAllFriendRequests: () => Promise<void>;
  acceptRequest: (requestId: string) => Promise<void>;
  declineRequest: (requestId: string) => Promise<void>;
  getFriends: () => Promise<void>;
}

export interface UserState {
  updateAvatarUrl: (formData: FormData) => Promise<void>;
}
