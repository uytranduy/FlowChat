import { Server } from "socket.io";
import http from "http";
import express from "express";
import { socketAuthMiddleware } from "../middlewares/socketMiddleware.js";
import { getUserConversationsForSocketIO } from "../controllers/conversationController.js";
import { config } from "../config/index.js";

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: {
    origin: config.CLIENT_URL,
    credentials: true,
  },
});

io.use(socketAuthMiddleware);

const onlineUsers = new Map<string, string>(); // {userId: socketId}

io.on("connection", async (socket) => {
  const user = socket.user;
  if (!user) {
    return;
  }

  const userIdStr = user._id.toString();

  onlineUsers.set(userIdStr, socket.id);

  io.emit("online-users", Array.from(onlineUsers.keys()));

  const conversationIds = await getUserConversationsForSocketIO(user._id);
  conversationIds.forEach((id) => {
    socket.join(id);
  });

  socket.on("join-conversation", (conversationId: string) => {
    socket.join(conversationId);
  });

  socket.join(userIdStr);

  socket.on("disconnect", () => {
    onlineUsers.delete(userIdStr);
    io.emit("online-users", Array.from(onlineUsers.keys()));
  });
});

export { io, app, server };
