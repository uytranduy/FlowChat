import api from "@/lib/axios";
import type { User } from "@/types/user";

export const userService = {
  uploadAvatar: async (formData: FormData) => {
    const res = await api.post("/users/uploadAvatar", formData, {
      headers: { "Content-Type": "multipart/form-data" },
    });

    if (res.status === 400) {
      throw new Error(res.data.message);
    }

    return res.data;
  },
  updateProfile: async (profile: Pick<User, "displayName" | "username" | "email" | "phone" | "bio">) => {
    const res = await api.patch("/users/me", profile);
    return res.data.user as User;
  },
  updatePreferences: async (preferences: Pick<User, "showOnlineStatus" | "notificationsEnabled">) => {
    const res = await api.patch("/users/me/preferences", preferences);
    return res.data.user as User;
  },
  changePassword: async (currentPassword: string, newPassword: string) => {
    const res = await api.patch("/users/me/password", { currentPassword, newPassword });
    return res.data as { message: string };
  },
  getPublicUser: async (userId: string) => {
    const res = await api.get(`/users/${userId}/public`);
    return res.data.user as Pick<User, "_id" | "username" | "displayName" | "avatarUrl" | "bio" | "isOnline" | "lastSeenAt" | "presenceVisible">;
  },
};
