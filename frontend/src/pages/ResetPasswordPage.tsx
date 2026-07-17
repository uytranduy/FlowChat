import { useState } from "react";
import { useSearchParams } from "react-router";
import { authService } from "@/services/authService";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import axios from "axios";

const ResetPasswordPage = () => {
  const [params] = useSearchParams();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    const token = params.get("token")?.trim();
    if (!token) return setMessage("Liên kết đặt lại mật khẩu không hợp lệ.");
    if (password.length < 6) return setMessage("Mật khẩu phải có ít nhất 6 ký tự.");
    if (password !== confirmPassword) return setMessage("Mật khẩu xác nhận không khớp.");
    setBusy(true);
    try {
      const response = await authService.resetPassword(token, password);
      setSuccess(true);
      setMessage(response.message);
    } catch (error) {
      const serverMessage = axios.isAxiosError(error)
        ? error.response?.data?.message
        : null;
      setMessage(typeof serverMessage === "string" ? serverMessage : "Không thể đặt lại mật khẩu.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="absolute inset-0 flex min-h-svh items-center justify-center bg-gradient-purple p-6">
      <Card className="w-full max-w-md border-border">
        <CardContent className="space-y-5 p-7">
          <h1 className="text-center text-2xl font-bold">Đặt mật khẩu mới</h1>
          {!success && (
            <>
              <div className="space-y-2">
                <Label htmlFor="new-password">Mật khẩu mới</Label>
                <Input id="new-password" type="password" value={password} onChange={(event) => setPassword(event.target.value)} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="confirm-password">Nhập lại mật khẩu</Label>
                <Input id="confirm-password" type="password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} />
              </div>
              <Button className="w-full" disabled={busy} onClick={() => void submit()}>
                {busy ? "Đang cập nhật…" : "Đặt lại mật khẩu"}
              </Button>
            </>
          )}
          {message && <div className="rounded-lg bg-muted p-3 text-sm">{message}</div>}
          <a href="/signin" className="block text-center text-sm underline">Quay lại đăng nhập</a>
        </CardContent>
      </Card>
    </div>
  );
};

export default ResetPasswordPage;
