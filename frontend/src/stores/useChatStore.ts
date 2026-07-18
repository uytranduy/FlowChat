import { chatService } from "@/services/chatService";
import type { ChatState } from "@/types/store";
import { create } from "zustand";
import { persist } from "zustand/middleware";
import { useAuthStore } from "./useAuthStore";
import { useSocketStore } from "./useSocketStore";

function mergeMessages(
  current: ChatState["messages"][string]["items"],
  incoming: ChatState["messages"][string]["items"]
) {
  const byId = new Map(current.map((message) => [message._id, message]));
  incoming.forEach((message) => byId.set(message._id, message));

  return Array.from(byId.values()).sort((left, right) => {
    const byCreatedAt =
      new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime();
    return byCreatedAt || left._id.localeCompare(right._id);
  });
}

export const useChatStore = create<ChatState>()(
  persist(
    (set, get) => ({
      conversations: [],
      messages: {},
      activeConversationId: null,
      replyingTo: null,
      convoLoading: false, // convo loading
      messageLoading: false,
      loading: false,

      setActiveConversation: (id) =>
        set({ activeConversationId: id, replyingTo: null }),
      setReplyingTo: (message) => set({ replyingTo: message }),
      reset: () => {
        set({
          conversations: [],
          messages: {},
          activeConversationId: null,
          replyingTo: null,
          convoLoading: false,
          messageLoading: false,
        });
      },
      fetchConversations: async () => {
        try {
          set({ convoLoading: true });
          const { conversations } = await chatService.fetchConversations();

          set({ conversations, convoLoading: false });
        } catch (error) {
          console.error("Lỗi xảy ra khi fetchConversations:", error);
          set({ convoLoading: false });
        }
      },
      fetchMessages: async (conversationId) => {
        const { activeConversationId, messages } = get();
        const { user } = useAuthStore.getState();

        const convoId = conversationId ?? activeConversationId;

        if (!convoId) return;

        const current = messages?.[convoId];
        const nextCursor =
          current?.nextCursor === undefined ? "" : current?.nextCursor;

        if (nextCursor === null) return;

        set({ messageLoading: true });

        try {
          const { messages: fetched, cursor } = await chatService.fetchMessages(
            convoId,
            nextCursor
          );

          const processed = fetched.map((m) => ({
            ...m,
            isOwn: m.senderId === user?._id,
          }));

          set((state) => {
            const prev = state.messages[convoId]?.items ?? [];
            const merged = prev.length > 0 ? [...processed, ...prev] : processed;

            return {
              messages: {
                ...state.messages,
                [convoId]: {
                  items: merged,
                  hasMore: !!cursor,
                  nextCursor: cursor ?? null,
                },
              },
            };
          });
        } catch (error) {
          console.error("Lỗi xảy ra khi fetchMessages:", error);
        } finally {
          set({ messageLoading: false });
        }
      },
      refreshLatestMessages: async (conversationId) => {
        const convoId = conversationId ?? get().activeConversationId;
        const { user } = useAuthStore.getState();
        if (!convoId) return;

        try {
          const { messages: fetched, cursor } =
            await chatService.fetchMessages(convoId);
          const processed = fetched.map((message) => ({
            ...message,
            isOwn: message.senderId === user?._id,
          }));

          set((state) => {
            const current = state.messages[convoId];
            const latest = processed.at(-1);
            return {
              messages: {
                ...state.messages,
                [convoId]: {
                  items: mergeMessages(current?.items ?? [], processed),
                  // `nextCursor` points to the oldest loaded page. Refreshing
                  // the newest page must not reset older-message pagination.
                  hasMore: current?.hasMore ?? Boolean(cursor),
                  nextCursor: current
                    ? current.nextCursor
                    : (cursor ?? null),
                },
              },
              conversations: latest
                ? state.conversations.map((conversation) => {
                    if (conversation._id !== convoId) return conversation;

                    const currentLastTime = conversation.lastMessage?.createdAt
                      ? new Date(conversation.lastMessage.createdAt).getTime()
                      : 0;
                    const latestTime = new Date(latest.createdAt).getTime();
                    if (currentLastTime > latestTime) return conversation;

                    const sender = conversation.participants.find(
                      (participant) => participant._id === latest.senderId
                    );
                    return {
                      ...conversation,
                      lastMessageAt: latest.createdAt,
                      lastMessage: {
                        _id: latest._id,
                        content: latest.content,
                        createdAt: latest.createdAt,
                        messageType: latest.messageType,
                        call: latest.call,
                        attachment: latest.attachment,
                        isRecalled: latest.isRecalled,
                        senderId: latest.senderId,
                        ...(sender
                          ? {
                              sender: {
                                _id: sender._id,
                                displayName: sender.displayName,
                                avatarUrl: sender.avatarUrl,
                              },
                            }
                          : {}),
                      },
                    };
                  })
                : state.conversations,
            };
          });
        } catch (error) {
          console.error("Lỗi xảy ra khi làm mới tin nhắn mới nhất:", error);
        }
      },
      sendDirectMessage: async (
        recipientId,
        content,
        file,
        replyToMessageId
      ) => {
        try {
          const { activeConversationId } = get();
          await chatService.sendDirectMessage(
            recipientId,
            content,
            file,
            activeConversationId || undefined,
            replyToMessageId
          );
          set((state) => ({
            conversations: state.conversations.map((c) =>
              c._id === activeConversationId ? { ...c, seenBy: [] } : c
            ),
          }));
        } catch (error) {
          console.error("Lỗi xảy ra khi gửi direct message", error);
          throw error;
        }
      },
      sendGroupMessage: async (
        conversationId,
        content,
        file,
        replyToMessageId
      ) => {
        try {
          await chatService.sendGroupMessage(
            conversationId,
            content,
            file,
            replyToMessageId
          );
          set((state) => ({
            conversations: state.conversations.map((c) =>
              c._id === get().activeConversationId ? { ...c, seenBy: [] } : c
            ),
          }));
        } catch (error) {
          console.error("Lỗi xảy ra gửi group message", error);
          throw error;
        }
      },
      addMessage: async (message) => {
        try {
          const { user } = useAuthStore.getState();
          const { fetchMessages } = get();

          message.isOwn = message.senderId === user?._id;

          const convoId = message.conversationId;

          let prevItems = get().messages[convoId]?.items ?? [];

          if (prevItems.length === 0) {
            await fetchMessages(message.conversationId);
            prevItems = get().messages[convoId]?.items ?? [];
          }

          set((state) => {
            if (prevItems.some((m) => m._id === message._id)) {
              return state;
            }

            return {
              messages: {
                ...state.messages,
                [convoId]: {
                  items: [...prevItems, message],
                  hasMore: state.messages[convoId].hasMore,
                  nextCursor: state.messages[convoId].nextCursor ?? undefined,
                },
              },
            };
          });
        } catch (error) {
          console.error("Lỗi xảy khi ra add message:", error);
        }
      },
      updateMessage: (message) => {
        const { user } = useAuthStore.getState();
        const normalized = {
          ...message,
          // An unpinned payload from an older server may omit these fields.
          // Normalize them so merging cannot retain the previous pin badge.
          pinnedAt: message.pinnedAt ?? null,
          pinnedBy: message.pinnedBy ?? null,
          isOwn: message.senderId === user?._id,
        };

        set((state) => ({
          replyingTo:
            state.replyingTo?._id === normalized._id
              ? normalized.isRecalled
                ? null
                : { ...state.replyingTo, ...normalized }
              : state.replyingTo,
          messages: Object.fromEntries(
            Object.entries(state.messages).map(([conversationId, page]) => [
              conversationId,
              {
                ...page,
                items: page.items.map((item) => {
                  if (item._id === normalized._id) {
                    return { ...item, ...normalized };
                  }

                  if (item.replyTo?.messageId === normalized._id) {
                    return {
                      ...item,
                      replyTo: {
                        ...item.replyTo,
                        content: normalized.content,
                        isRecalled: Boolean(normalized.isRecalled),
                      },
                    };
                  }

                  return item;
                }),
              },
            ])
          ),
          conversations: state.conversations.map((conversation) =>
            conversation.lastMessage?._id === normalized._id
              ? {
                  ...conversation,
                  lastMessage: {
                    ...conversation.lastMessage,
                    content: normalized.isRecalled
                      ? "Tin nhắn đã thu hồi"
                      : normalized.content,
                    messageType: normalized.messageType,
                    call: normalized.call,
                    attachment: normalized.attachment,
                    isRecalled: normalized.isRecalled,
                  },
                }
              : conversation
          ),
        }));
      },
      recallMessage: async (messageId) => {
        const message = await chatService.recallMessage(messageId);
        get().updateMessage(message);
      },
      setReaction: async (messageId, emoji) => {
        const message = await chatService.setReaction(messageId, emoji);
        get().updateMessage(message);
      },
      removeReaction: async (messageId) => {
        const message = await chatService.removeReaction(messageId);
        get().updateMessage(message);
      },
      forwardMessage: async (messageId, conversationId) => {
        const message = await chatService.forwardMessage(
          messageId,
          conversationId
        );
        await get().addMessage(message);
      },
      updateMessagePin: async (conversationId, messageId, pinned) => {
        const message = await chatService.updateMessagePin(
          conversationId,
          messageId,
          pinned
        );
        get().updateMessage(message);
        window.dispatchEvent(
          new CustomEvent("flowchat:pins-changed", {
            detail: { conversationId },
          })
        );
      },
      updateConversation: (conversation) => {
        set((state) => {
          const conversations = state.conversations.map((current) =>
            current._id === conversation._id
              ? { ...current, ...conversation }
              : current
          );

          conversations.sort(
            (a, b) =>
              new Date(b.lastMessageAt || b.updatedAt).getTime() -
              new Date(a.lastMessageAt || a.updatedAt).getTime()
          );

          return { conversations };
        });
      },
      removeConversation: (conversationId) => {
        set((state) => ({
          conversations: state.conversations.filter(
            (conversation) => conversation._id !== conversationId
          ),
          activeConversationId:
            state.activeConversationId === conversationId
              ? null
              : state.activeConversationId,
          messages: Object.fromEntries(
            Object.entries(state.messages).filter(
              ([id]) => id !== conversationId
            )
          ),
        }));
      },
      clearConversationMessages: (conversationId) => {
        set((state) => ({
          messages: Object.fromEntries(
            Object.entries(state.messages).filter(
              ([id]) => id !== conversationId
            )
          ),
          replyingTo:
            state.replyingTo?.conversationId === conversationId
              ? null
              : state.replyingTo,
        }));
      },
      markAsSeen: async () => {
        try {
          const { user } = useAuthStore.getState();
          const { activeConversationId, conversations } = get();

          if (!activeConversationId || !user) {
            return;
          }

          const convo = conversations.find((c) => c._id === activeConversationId);

          if (!convo) {
            return;
          }

          if ((convo.unreadCounts?.[user._id] ?? 0) === 0) {
            return;
          }

          await chatService.markAsSeen(activeConversationId);

          set((state) => ({
            conversations: state.conversations.map((c) =>
              c._id === activeConversationId && c.lastMessage
                ? {
                    ...c,
                    unreadCounts: {
                      ...c.unreadCounts,
                      [user._id]: 0,
                    },
                  }
                : c
            ),
          }));
        } catch (error) {
          console.error("Lỗi xảy ra khi gọi markAsSeen trong store", error);
        }
      },
      addConvo: (convo) => {
        set((state) => {
          const exists = state.conversations.some(
            (c) => c._id.toString() === convo._id.toString()
          );

          return {
            conversations: exists
              ? state.conversations
              : [convo, ...state.conversations],
            activeConversationId: convo._id,
          };
        });
      },
      createConversation: async (type, name, memberIds) => {
        try {
          set({ loading: true });
          const conversation = await chatService.createConversation(
            type,
            name,
            memberIds
          );

          get().addConvo(conversation);

          useSocketStore
            .getState()
            .socket?.emit("join-conversation", conversation._id);
          return conversation;
        } catch (error) {
          console.error("Lỗi xảy ra khi gọi createConversation trong store", error);
          throw error;
        } finally {
          set({ loading: false });
        }
      },
    }),
    {
      name: "chat-storage",
      partialize: (state) => ({ conversations: state.conversations }),
    }
  )
);
