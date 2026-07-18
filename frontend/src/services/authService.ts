import api from "@/lib/axios";

export const authService = {
  signUp: async (
    username: string,
    password: string,
    email: string,
    firstName: string,
    lastName: string
  ) => {
    const res = await api.post(
      "/auth/signup",
      { username, password, email, firstName, lastName },
      { withCredentials: true }
    );

    return res.data;
  },

  verifyEmail: async (token: string) => {
    const res = await api.post("/auth/verify-email", { token });
    return res.data as { message: string };
  },

  resendVerification: async (email: string) => {
    const res = await api.post("/auth/resend-verification", { email });
    return res.data as { message: string };
  },

  forgotPassword: async (email: string) => {
    const res = await api.post("/auth/forgot-password", { email });
    return res.data as {
      accountType: "local" | "google" | "unknown";
      message: string;
    };
  },

  resetPassword: async (token: string, password: string) => {
    const res = await api.post("/auth/reset-password", { token, password });
    return res.data as { message: string };
  },

  signIn: async (username: string, password: string) => {
    const res = await api.post(
      "auth/signin",
      { username, password },
      { withCredentials: true }
    );
    return res.data; // access token
  },

  signInWithGoogle: async (idToken: string) => {
    const res = await api.post(
      "/auth/google",
      { idToken },
      { withCredentials: true }
    );
    return res.data;
  },

  signOut: async () => {
    return api.post("/auth/signout", { withCredentials: true });
  },

  fetchMe: async () => {
    const res = await api.get("/users/me", { withCredentials: true });
    return res.data.user;
  },

  refresh: async () => {
    const res = await api.post("/auth/refresh", { withCredentials: true });
    return res.data.accessToken;
  },
};
