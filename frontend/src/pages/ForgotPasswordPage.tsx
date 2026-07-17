import { useState } from "react";
import { authService } from "@/services/authService";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import axios from "axios";

function errorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const message = error.response?.data?.message;
    if (typeof message === "string") return message;
  }
  return "Không thể gửi email. Vui lòng thử lại.";
}

const ForgotPasswordPage = () => {
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [isGoogleAccount, setIsGoogleAccount] = useState(false);
  const [busy, setBusy] = useState(false);

  const submit = async (mode: "reset" | "verify") => {
    if (!email.trim()) {
      setMessage("Vui lòng nhập địa chỉ email.");
      return;
    }
    setBusy(true);
    setMessage(null);
    setIsGoogleAccount(false);
    try {
      if (mode === "verify") {
        const response = await authService.resendVerification(email.trim());
        setMessage(response.message);
      } else {
        const response = await authService.forgotPassword(email.trim());
        setMessage(response.message);
        setIsGoogleAccount(response.accountType === "google");
      }
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="absolute inset-0 flex min-h-svh items-center justify-center bg-gradient-purple p-6">
      <Card className="w-full max-w-md border-border">
        <CardContent className="space-y-6 p-7">
          <div className="space-y-2 text-center">
            <img src="/logo.svg" alt="FlowChat" className="mx-auto" />
            <h1 className="text-2xl font-bold">Quên mật khẩu</h1>
            <p className="text-sm text-muted-foreground">
              Nhập email đăng ký để nhận liên kết đặt lại mật khẩu.
            </p>
          </div>
          <div className="space-y-2">
            <Label htmlFor="recovery-email">Email</Label>
            <Input
              id="recovery-email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="ban@gmail.com"
              disabled={busy}
            />
          </div>
          {message && (
            <div className="rounded-lg border border-border bg-muted p-3 text-sm">
              {message}
              {isGoogleAccount && (
                <a
                  className="mt-2 block font-medium text-primary underline"
                  href="https://accounts.google.com/signin/recovery"
                  target="_blank"
                  rel="noreferrer"
                >
                  Khôi phục mật khẩu Google
                </a>
              )}
            </div>
          )}
          <Button className="w-full" disabled={busy} onClick={() => void submit("reset")}>
            {busy ? "Đang gửi…" : "Gửi liên kết đặt lại mật khẩu"}
          </Button>
          <Button
            className="w-full"
            variant="outline"
            disabled={busy}
            onClick={() => void submit("verify")}
          >
            Gửi lại email xác minh
          </Button>
          <a href="/signin" className="block text-center text-sm underline">
            Quay lại đăng nhập
          </a>
        </CardContent>
      </Card>
    </div>
  );
};

export default ForgotPasswordPage;
