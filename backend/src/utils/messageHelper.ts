import { HydratedDocument, Types } from "mongoose";
import { IConversation } from "../models/Conversation.js";
import { IMessage } from "../models/Message.js";
import { Server } from "socket.io";

export const updateConversationAfterCreateMessage = (
  conversation: HydratedDocument<IConversation>,
  message: HydratedDocument<IMessage>,
  senderId: Types.ObjectId | string
): void => {
  conversation.set({
    seenBy: [],
    lastMessageAt: message.createdAt,
    lastMessage: {
      _id: message._id?.toString(),
      content: message.content,
      senderId: new Types.ObjectId(senderId),
      createdAt: message.createdAt,
    },
  });

  conversation.participants.forEach((p) => {
    const memberId = p.userId.toString();
    const isSender = memberId === senderId.toString();
    const prevCount = conversation.unreadCounts.get(memberId) || 0;
    conversation.unreadCounts.set(memberId, isSender ? 0 : prevCount + 1);
  });
};

export const emitNewMessage = (
  io: Server,
  conversation: HydratedDocument<IConversation>,
  message: HydratedDocument<IMessage>
): void => {
  io.to(conversation._id.toString()).emit("new-message", {
    message,
    conversation: {
      _id: conversation._id,
      lastMessage: conversation.lastMessage,
      lastMessageAt: conversation.lastMessageAt,
    },
    unreadCounts: conversation.unreadCounts,
  });
};
