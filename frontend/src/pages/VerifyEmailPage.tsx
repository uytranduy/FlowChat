import { useEffect, useState } from "react";
import { useSearchParams } from "react-router";
import { authService } from "@/services/authService";
import axios from "axios";

const VerifyEmailPage = () => {
  const [params] = useSearchParams();
  const [message, setMessage] = useState("Đang xác minh email…");
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    const token = params.get("token")?.trim();
    if (!token) {
      setMessage("Liên kết xác minh không hợp lệ.");
      return;
    }
    void authService
      .verifyEmail(token)
      .then((response) => {
        setSuccess(true);
        setMessage(response.message);
      })
      .catch((error: unknown) => {
        const serverMessage = axios.isAxiosError(error)
          ? error.response?.data?.message
          : null;
        setMessage(
          typeof serverMessage === "string"
            ? serverMessage
            : "Không thể xác minh email."
        );
      });
  }, [params]);

  return (
    <div className="absolute inset-0 flex min-h-svh items-center justify-center bg-gradient-purple p-6">
      <div className="w-full max-w-md rounded-xl border bg-card p-8 text-center shadow-lg">
        <h1 className="text-2xl font-bold">Xác minh email FlowChat</h1>
        <p className="mt-4 text-muted-foreground">{message}</p>
        <a
          href={success ? "/signin" : "/forgot-password"}
          className="mt-6 inline-block text-primary underline"
        >
          {success ? "Đăng nhập FlowChat" : "Gửi lại email xác minh"}
        </a>
      </div>
    </div>
  );
};

export default VerifyEmailPage;
