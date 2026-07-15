import api from "@/lib/axios";
import type { ConversationResponse, Message } from "@/types/chat";

interface FetchMessageProps {
  messages: Message[];
  cursor?: string;
}

const pageLimit = 50;

function appendTextField(formData: FormData, name: string, value?: string) {
  if (value) formData.append(name, value);
}

export const chatService = {
  async fetchConversations(): Promise<ConversationResponse> {
    const res = await api.get("/conversations");
    return res.data;
  },

  async fetchMessages(id: string, cursor?: string): Promise<FetchMessageProps> {
    const normalizedCursor = cursor?.trim();
    const res = await api.get(`/conversations/${id}/messages`, {
      params: {
        limit: pageLimit,
        ...(normalizedCursor ? { cursor: normalizedCursor } : {}),
      },
    });

    return { messages: res.data.messages, cursor: res.data.nextCursor };
  },

  async sendDirectMessage(
    recipientId: string,
    content: string = "",
    file?: File,
    conversationId?: string,
    replyToMessageId?: string
  ) {
    const payload = file
      ? (() => {
          const formData = new FormData();
          formData.append("file", file, file.name);
          formData.append("recipientId", recipientId);
          appendTextField(formData, "content", content.trim());
          appendTextField(formData, "conversationId", conversationId);
          appendTextField(formData, "replyToMessageId", replyToMessageId);
          return formData;
        })()
      : {
          recipientId,
          content,
          conversationId,
          replyToMessageId,
        };

    const res = await api.post("/messages/direct", payload);

    return res.data.message;
  },

  async sendGroupMessage(
    conversationId: string,
    content: string = "",
    file?: File,
    replyToMessageId?: string
  ) {
    const payload = file
      ? (() => {
          const formData = new FormData();
          formData.append("file", file, file.name);
          formData.append("conversationId", conversationId);
          appendTextField(formData, "content", content.trim());
          appendTextField(formData, "replyToMessageId", replyToMessageId);
          return formData;
        })()
      : { conversationId, content, replyToMessageId };

    const res = await api.post("/messages/group", payload);
    return res.data.message;
  },

  async markAsSeen(conversationId: string) {
    const res = await api.patch(`/conversations/${conversationId}/seen`);
    return res.data;
  },

  async recallMessage(messageId: string): Promise<Message> {
    const res = await api.patch(`/messages/${messageId}/recall`);
    return res.data.message;
  },

  async setReaction(messageId: string, emoji: string): Promise<Message> {
    const res = await api.put(`/messages/${messageId}/reaction`, { emoji });
    return res.data.message;
  },

  async removeReaction(messageId: string): Promise<Message> {
    const res = await api.delete(`/messages/${messageId}/reaction`);
    return res.data.message;
  },

  async forwardMessage(
    messageId: string,
    conversationId: string
  ): Promise<Message> {
    const res = await api.post(`/messages/${messageId}/forward`, {
      conversationId,
    });
    return res.data.message;
  },

  async createConversation(
    type: "direct" | "group",
    name: string,
    memberIds: string[]
  ) {
    const res = await api.post("/conversations", { type, name, memberIds });
    return res.data.conversation;
  },
  async addGroupMember(conversationId: string, userId: string) {
    const res = await api.post(`/conversations/${conversationId}/members`, { userId });
    return res.data.conversation;
  },
  async transferGroupOwnership(conversationId: string, userId: string) {
    const res = await api.patch(`/conversations/${conversationId}/owner`, { userId });
    return res.data.conversation;
  },
  async updateGroupInvitePermission(
    conversationId: string,
    allowMembersToInvite: boolean
  ) {
    const res = await api.patch(
      `/conversations/${conversationId}/group-settings`,
      { allowMembersToInvite }
    );
    return res.data.conversation;
  },
  async leaveGroup(conversationId: string): Promise<void> {
    await api.delete(`/conversations/${conversationId}/members/me`);
  },
  async dissolveGroup(conversationId: string) {
    const res = await api.patch(`/conversations/${conversationId}/dissolve`);
    return res.data.conversation;
  },
  async removeDissolvedGroup(conversationId: string): Promise<void> {
    await api.delete(`/conversations/${conversationId}`);
  },
};
