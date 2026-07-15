import api from "@/lib/axios";

export interface UserBlockStatus {
  userId: string;
  isBlocked: boolean;
  isBlockedByMe: boolean;
  hasBlockedMe: boolean;
}

export interface BlockedUser {
  _id: string;
  username: string;
  displayName: string;
  avatarUrl?: string;
  bio?: string;
  blockedAt: string;
}

export const blockService = {
  async getStatus(userId: string): Promise<UserBlockStatus> {
    const response = await api.get(`/users/blocks/${userId}/status`);
    return response.data;
  },
  async block(userId: string): Promise<UserBlockStatus> {
    const response = await api.post(`/users/blocks/${userId}`);
    return response.data.status;
  },
  async unblock(userId: string): Promise<UserBlockStatus> {
    const response = await api.delete(`/users/blocks/${userId}`);
    return response.data.status;
  },
  async getBlockedUsers(): Promise<BlockedUser[]> {
    const response = await api.get("/users/blocks");
    return response.data.blockedUsers ?? [];
  },
};
