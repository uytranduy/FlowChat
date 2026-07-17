import { create } from "zustand";
import { toast } from "sonner";
import { authService } from "@/services/authService";
import type { AuthState } from "@/types/store";
import { persist } from "zustand/middleware";
import { useChatStore } from "./useChatStore";
import axios from "axios";

function authErrorMessage(error: unknown, fallback: string): string {
  if (axios.isAxiosError(error)) {
    const message = error.response?.data?.message;
    if (typeof message === "string" && message.trim()) return message;
  }
  return error instanceof Error && error.message ? error.message : fallback;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      accessToken: null,
      user: null,
      loading: false,

      setAccessToken: (accessToken) => {
        set({ accessToken });
      },
      setUser: (user) => {
        set({ user });
      },
      clearState: () => {
        set({ accessToken: null, user: null, loading: false });
        useChatStore.getState().reset();
        localStorage.clear();
        sessionStorage.clear();
      },
      signUp: async (username, password, email, firstName, lastName) => {
        try {
          set({ loading: true });

          //  gọi api
          const response = await authService.signUp(
            username,
            password,
            email,
            firstName,
            lastName
          );

          toast.success(
            response?.message ||
              "Đăng ký thành công. Vui lòng kiểm tra email để xác minh tài khoản."
          );
          return true;
        } catch (error) {
          console.error(error);
          toast.error(authErrorMessage(error, "Đăng ký không thành công"));
          return false;
        } finally {
          set({ loading: false });
        }
      },
      signIn: async (username, password) => {
        try {
          get().clearState();
          set({ loading: true });

          const { accessToken } = await authService.signIn(username, password);
          get().setAccessToken(accessToken);

          await get().fetchMe();
          useChatStore.getState().fetchConversations();

          toast.success("Chào mừng bạn quay lại với FlowChat 🎉");
          return true;
        } catch (error) {
          console.error(error);
          toast.error(authErrorMessage(error, "Đăng nhập không thành công!"));
          return false;
        } finally {
          set({ loading: false });
        }
      },
      signInWithGoogle: async (idToken) => {
        try {
          get().clearState();
          set({ loading: true });
          const { accessToken } = await authService.signInWithGoogle(idToken);
          get().setAccessToken(accessToken);
          await get().fetchMe();
          await useChatStore.getState().fetchConversations();
          toast.success("Đăng nhập bằng Google thành công 🎉");
          return true;
        } catch (error) {
          console.error(error);
          toast.error("Đăng nhập bằng Google không thành công!");
          return false;
        } finally {
          set({ loading: false });
        }
      },
      signOut: async () => {
        try {
          get().clearState();
          await authService.signOut();
          toast.success("Logout thành công!");
        } catch (error) {
          console.error(error);
          toast.error("Lỗi xảy ra khi logout. Hãy thử lại!");
        }
      },
      fetchMe: async () => {
        try {
          set({ loading: true });
          const user = await authService.fetchMe();

          set({ user });
        } catch (error) {
          console.error(error);
          set({ user: null, accessToken: null });
          toast.error("Lỗi xảy ra khi lấy dữ liệu người dùng. Hãy thử lại!");
        } finally {
          set({ loading: false });
        }
      },
      refresh: async () => {
        try {
          set({ loading: true });
          const { user, fetchMe, setAccessToken } = get();
          const accessToken = await authService.refresh();

          setAccessToken(accessToken);

          if (!user) {
            await fetchMe();
          }
        } catch (error) {
          console.error(error);
          toast.error("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại!");
          get().clearState();
        } finally {
          set({ loading: false });
        }
      },
    }),
    {
      name: "auth-storage",
      partialize: (state) => ({ user: state.user }), // chỉ persist user
    }
  )
);
