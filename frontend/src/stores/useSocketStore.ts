import { create } from "zustand";
import { io, type Socket } from "socket.io-client";
import { useAuthStore } from "./useAuthStore";
import type { SocketState } from "@/types/store";
import { useChatStore } from "./useChatStore";
import { useCallStore } from "./useCallStore";
import type { Conversation, Message } from "@/types/chat";
import { toast } from "sonner";
import { useFriendStore } from "./useFriendStore";
import type { FriendRequest } from "@/types/user";

const baseURL = import.meta.env.VITE_SOCKET_URL;
const notifiedMessageIds = new Set<string>();

function rememberNotification(messageId: string) {
  notifiedMessageIds.add(messageId);
  window.setTimeout(() => notifiedMessageIds.delete(messageId), 15000);
}

function readConversationId(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null) return null;
  const conversationId = (payload as Record<string, unknown>).conversationId;
  return typeof conversationId === "string" && conversationId.length > 0
    ? conversationId
    : null;
}

function scheduleCallHistoryRefresh(conversationId: string) {
  // `call:ended` closes the overlay immediately. The backend then persists the
  // call message, so retry the newest page briefly to cover database/socket
  // timing without changing the cursor used for older-message pagination.
  [250, 1_000, 2_000].forEach((delay) => {
    window.setTimeout(() => {
      void useChatStore.getState().refreshLatestMessages(conversationId);
    }, delay);
  });
}

function messageNotificationPreview(message: Message): string {
  if (message.messageType === "attachment" || message.attachment) {
    const caption = message.content?.trim();
    if (caption) return caption;
    switch (message.attachment?.kind) {
      case "image":
        return "Đã gửi cho bạn một ảnh";
      case "video":
        return "Đã gửi cho bạn một video";
      default:
        return `Đã gửi tệp ${message.attachment?.fileName || "đính kèm"}`;
    }
  }
  if (message.messageType === "call") return "Có một cuộc gọi mới";
  return message.content?.trim() || "Bạn có tin nhắn mới";
}

function notifyIncomingMessage(message: Message, conversation?: Conversation) {
  const user = useAuthStore.getState().user;
  if (!user || user.notificationsEnabled === false || message.senderId === user._id) return;

  const sender = conversation?.participants.find(
    (participant) => participant._id === message.senderId
  );
  const title =
    conversation?.type === "group"
      ? `${sender?.displayName || "Thành viên"} · ${
          conversation.group?.name || "Nhóm chat"
        }`
      : sender?.displayName || "Tin nhắn FlowChat";
  const description = messageNotificationPreview(message);
  const openConversation = () => {
    const chatState = useChatStore.getState();
    chatState.setActiveConversation(message.conversationId);
    void chatState.refreshLatestMessages(message.conversationId);
    window.focus();
  };

  toast.message(title, {
    description,
    duration: 6000,
    action: {
      label: "Mở",
      onClick: openConversation,
    },
  });

  if (
    document.hidden &&
    "Notification" in window &&
    Notification.permission === "granted"
  ) {
    const notification = new Notification(title, {
      body: description,
      icon: sender?.avatarUrl || "/favicon.ico",
      tag: `flowchat-${message.conversationId}`,
    });
    notification.onclick = () => {
      notification.close();
      openConversation();
    };
  }
}

export const useSocketStore = create<SocketState>((set, get) => ({
  socket: null,
  isConnected: false,
  onlineUsers: [],
  relationshipRevision: 0,
  lastSeenByUser: {},
  connectSocket: () => {
    const accessToken = useAuthStore.getState().accessToken;
    const existingSocket = get().socket;

    if (existingSocket) return; // tránh tạo nhiều socket

    const socket: Socket = io(baseURL, {
      auth: { token: accessToken },
      transports: ["websocket"],
      autoConnect: false,
    });

    set({ socket });

    socket.on("connect", () => {
      console.log("Đã kết nối với socket");
      set({ isConnected: true });
    });

    socket.on("disconnect", () => {
      useCallStore.getState().handleSocketDisconnect();
      set({ isConnected: false, onlineUsers: [] });
    });

    // Register call signaling before the socket connects so an incoming call
    // cannot be lost between the first connection and a React effect mount.
    socket.on("call:incoming", (payload: unknown) => {
      useCallStore.getState().handleIncoming(payload);
    });

    socket.on("call:accepted", (payload: unknown) => {
      void useCallStore.getState().handleAccepted(payload);
    });

    socket.on("call:ended", (payload: unknown) => {
      const conversationId =
        readConversationId(payload) ?? useCallStore.getState().conversationId;
      useCallStore.getState().handleEnded(payload);
      if (conversationId) scheduleCallHistoryRefresh(conversationId);
    });

    socket.on("call:signal", (payload: unknown) => {
      useCallStore.getState().handleSignal(payload);
    });

    // online users
    socket.on("online-users", (userIds) => {
      set((state) => {
        const nextOnline = new Set<string>(userIds);
        const lastSeenByUser = { ...state.lastSeenByUser };
        const disconnectedAt = new Date().toISOString();
        state.onlineUsers.forEach((userId) => {
          if (!nextOnline.has(userId)) lastSeenByUser[userId] = disconnectedAt;
        });
        return { onlineUsers: userIds, lastSeenByUser };
      });
    });

    socket.on(
      "friend-request:received",
      ({ request }: { request?: FriendRequest }) => {
        void useFriendStore.getState().getAllFriendRequests();
        if (useAuthStore.getState().user?.notificationsEnabled === false) return;
        const senderName = request?.from?.displayName || "Một người dùng";
        const description = `${senderName} đã gửi cho bạn một lời mời kết bạn.`;

        toast.message("Lời mời kết bạn mới", {
          description,
          duration: 7000,
        });

        if (
          document.hidden &&
          "Notification" in window &&
          Notification.permission === "granted"
        ) {
          const notification = new Notification("Lời mời kết bạn mới", {
            body: description,
            icon: request?.from?.avatarUrl || "/favicon.ico",
            tag: `friend-request-${request?._id || senderName}`,
          });
          notification.onclick = () => {
            notification.close();
            window.focus();
          };
        }
      }
    );

    socket.on("friend-request:updated", () => {
      const friendStore = useFriendStore.getState();
      void friendStore.getAllFriendRequests();
      void friendStore.getFriends();
    });

    socket.on("user-block:updated", () => {
      set((state) => ({
        relationshipRevision: state.relationshipRevision + 1,
      }));
    });

    // new message
    socket.on("new-message", ({ message, conversation, unreadCounts }) => {
      const chatState = useChatStore.getState();
      const knownConversation = chatState.conversations.find(
        (item) => item._id === message.conversationId
      );
      const notificationAlreadyHandled = notifiedMessageIds.has(message._id);
      rememberNotification(message._id);
      void chatState.addMessage(message);

      const emittedMessageIsLatest =
        conversation.lastMessage?._id?.toString() === message._id?.toString();
      if (emittedMessageIsLatest) {
        const lastMessage = {
          _id: conversation.lastMessage._id,
          content: message.content ?? null,
          createdAt: conversation.lastMessage.createdAt,
          messageType: message.messageType,
          call: message.call,
          attachment: message.attachment
            ? {
                kind: message.attachment.kind,
                fileName: message.attachment.fileName,
              }
            : null,
          isRecalled: message.isRecalled,
          sender: {
            _id: conversation.lastMessage.senderId,
            displayName: "",
            avatarUrl: null,
          },
        };

        chatState.updateConversation({
          ...conversation,
          lastMessage,
          unreadCounts,
        });
      } else {
        // A delayed call-history write may be emitted after a newer message.
        // Keep the newer sidebar preview while still applying unread counts.
        chatState.updateConversation({
          _id: conversation._id,
          unreadCounts,
        });
      }

      const isVisibleActiveConversation =
        chatState.activeConversationId === message.conversationId &&
        document.visibilityState === "visible";

      if (isVisibleActiveConversation) {
        void useChatStore.getState().markAsSeen();
      } else if (!notificationAlreadyHandled) {
        notifyIncomingMessage(message, knownConversation);
      }

      if (!knownConversation) {
        void useChatStore.getState().fetchConversations();
      }
    });

    // Fallback user-room event. Normally `new-message` arrives first; this
    // keeps badges and browser notifications working for newly-created chats
    // whose room membership was not yet known by an older client.
    socket.on(
      "message-notification",
      ({
        conversationId,
        messageId,
        senderId,
        messageType,
        preview,
        createdAt,
        unreadCount,
      }) => {
        if (!messageId || notifiedMessageIds.has(messageId)) return;
        rememberNotification(messageId);

        const chatState = useChatStore.getState();
        const conversation = chatState.conversations.find(
          (item) => item._id === conversationId
        );
        const fallbackMessage: Message = {
          _id: messageId,
          conversationId,
          senderId,
          content: preview || "Bạn có tin nhắn mới",
          messageType,
          createdAt,
        };

        if (conversation) {
          const currentUser = useAuthStore.getState().user;
          chatState.updateConversation({
            _id: conversationId,
            lastMessageAt: createdAt,
            lastMessage: {
              _id: messageId,
              content: preview,
              createdAt,
              messageType,
              senderId,
            },
            unreadCounts: currentUser
              ? {
                  ...conversation.unreadCounts,
                  [currentUser._id]: unreadCount,
                }
              : conversation.unreadCounts,
          });
        } else {
          void chatState.fetchConversations();
        }

        const isVisibleActiveConversation =
          chatState.activeConversationId === conversationId &&
          document.visibilityState === "visible";
        if (!isVisibleActiveConversation) {
          notifyIncomingMessage(fallbackMessage, conversation);
        }
      }
    );

    socket.on("message-updated", ({ message }) => {
      useChatStore.getState().updateMessage(message);
    });

    // read message
    socket.on("read-message", ({ conversation, lastMessage }) => {
      const updated = {
        _id: conversation._id,
        lastMessage,
        lastMessageAt: conversation.lastMessageAt,
        unreadCounts: conversation.unreadCounts,
        seenBy: conversation.seenBy,
      };

      useChatStore.getState().updateConversation(updated);
    });

    // new group chat
    socket.on("new-group", (conversation) => {
      useChatStore.getState().addConvo(conversation);
      socket.emit("join-conversation", conversation._id);
    });

    socket.on("conversation:updated", (conversation: Conversation) => {
      useChatStore.getState().updateConversation(conversation);
    });

    socket.on("conversation:left", ({ conversationId }) => {
      if (typeof conversationId === "string") {
        useChatStore.getState().removeConversation(conversationId);
      }
    });

    socket.on("conversation:dissolved", (conversation: Conversation) => {
      const chatStore = useChatStore.getState();
      chatStore.updateConversation(conversation);
      chatStore.clearConversationMessages(conversation._id);
      void chatStore.refreshLatestMessages(conversation._id);
    });

    socket.on("conversation:removed", ({ conversationId }) => {
      if (typeof conversationId === "string") {
        useChatStore.getState().removeConversation(conversationId);
      }
    });

    socket.connect();
  },
  disconnectSocket: () => {
    const socket = get().socket;
    if (socket) {
      socket.disconnect();
      set({ socket: null, isConnected: false, onlineUsers: [] });
    }
  },
}));
