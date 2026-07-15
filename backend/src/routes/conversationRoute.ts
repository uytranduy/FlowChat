import express, { Router } from "express";
import {
  createConversation,
  getConversations,
  getMessageById,
  getMessages,
  getMessagesAround,
  markAsSeen,
  addGroupMember,
  transferGroupOwnership,
  updateGroupInvitePermission,
  leaveGroup,
  dissolveGroup,
  removeDissolvedGroup,
} from "../controllers/conversationController.js";
import {
  checkConversationMembership,
  checkFriendship,
} from "../middlewares/friendMiddleware.js";

const router: Router = express.Router();

router.post("/", checkFriendship, createConversation);
router.get("/", getConversations);
router.get(
  "/:conversationId/messages/:messageId/around",
  checkConversationMembership,
  getMessagesAround
);
router.get(
  "/:conversationId/messages/:messageId",
  checkConversationMembership,
  getMessageById
);
router.get("/:conversationId/messages", checkConversationMembership, getMessages);
router.post("/:conversationId/members", checkConversationMembership, addGroupMember);
router.patch("/:conversationId/owner", checkConversationMembership, transferGroupOwnership);
router.patch("/:conversationId/group-settings", checkConversationMembership, updateGroupInvitePermission);
router.delete("/:conversationId/members/me", checkConversationMembership, leaveGroup);
router.patch("/:conversationId/dissolve", checkConversationMembership, dissolveGroup);
router.delete("/:conversationId", checkConversationMembership, removeDissolvedGroup);
router.patch("/:conversationId/seen", checkConversationMembership, markAsSeen);

export default router;
