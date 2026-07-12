import mongoose, { Schema, Types } from "mongoose";

export interface IParticipant {
  userId: Types.ObjectId;
  joinedAt?: Date;
}

export interface IGroup {
  name?: string;
  createdBy?: Types.ObjectId;
}

export interface ILastMessage {
  _id?: string;
  content?: string | null;
  senderId?: Types.ObjectId;
  createdAt?: Date | null;
}

export interface IConversation {
  type: "direct" | "group";
  participants: IParticipant[];
  group?: IGroup;
  lastMessageAt?: Date;
  seenBy: Types.ObjectId[];
  lastMessage?: ILastMessage | null;
  unreadCounts: Map<string, number>;
  createdAt?: Date;
  updatedAt?: Date;
}

const participantSchema = new Schema<IParticipant>(
  {
    userId: {
      type: Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    joinedAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    _id: false,
  }
);

const groupSchema = new Schema<IGroup>(
  {
    name: {
      type: String,
      trim: true,
    },
    createdBy: {
      type: Schema.Types.ObjectId,
      ref: "User",
    },
  },
  {
    _id: false,
  }
);

const lastMessageSchema = new Schema<ILastMessage>(
  {
    _id: { type: String },
    content: {
      type: String,
      default: null,
    },
    senderId: {
      type: Schema.Types.ObjectId,
      ref: "User",
    },
    createdAt: {
      type: Date,
      default: null,
    },
  },
  {
    _id: false,
  }
);

const conversationSchema = new Schema<IConversation>(
  {
    type: {
      type: String,
      enum: ["direct", "group"],
      required: true,
    },
    participants: {
      type: [participantSchema],
      required: true,
    },
    group: {
      type: groupSchema,
    },
    lastMessageAt: {
      type: Date,
    },
    seenBy: [
      {
        type: Schema.Types.ObjectId,
        ref: "User",
      },
    ],
    lastMessage: {
      type: lastMessageSchema,
      default: null,
    },
    unreadCounts: {
      type: Map,
      of: Number,
      default: {},
    },
  },
  {
    timestamps: true,
  }
);

// We keep the exact index from the original file (which contains the participant typo/behavior)
conversationSchema.index({
  "participant.userId": 1,
  lastMessageAt: -1,
});

const Conversation = mongoose.model<IConversation>("Conversation", conversationSchema);
export default Conversation;
