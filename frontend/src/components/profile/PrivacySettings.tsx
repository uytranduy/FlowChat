import { useState } from "react";
import { Bell, Loader2, Shield, ShieldBan } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { userService } from "@/services/userService";
import { blockService, type BlockedUser } from "@/services/blockService";
import UserAvatar from "../chat/UserAvatar";
import { useAuthStore } from "@/stores/useAuthStore";

function apiError(error: unknown, fallback: string) {
  return (error as { response?: { data?: { message?: string } } }).response?.data?.message || fallback;
}

const PrivacySettings = () => {
  const user = useAuthStore((state) => state.user);
  const isGoogleAccount = user?.authProvider === "google";
  const [passwordOpen, setPasswordOpen] = useState(false);
  const [blocksOpen, setBlocksOpen] = useState(false);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [pending, setPending] = useState(false);
  const [blockedUsers, setBlockedUsers] = useState<BlockedUser[]>([]);

  const changePassword = async () => {
    if (newPassword !== confirmPassword) {
      toast.error("Mật khẩu xác nhận không khớp.");
      return;
    }
    setPending(true);
    try {
      await userService.changePassword(currentPassword, newPassword);
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      setPasswordOpen(false);
      toast.success("Đã đổi mật khẩu.");
    } catch (error) {
      toast.error(apiError(error, "Không thể đổi mật khẩu."));
    } finally {
      setPending(false);
    }
  };

  const openBlocks = async () => {
    setBlocksOpen(true);
    setPending(true);
    try {
      setBlockedUsers(await blockService.getBlockedUsers());
    } catch (error) {
      toast.error(apiError(error, "Không thể tải danh sách chặn."));
    } finally {
      setPending(false);
    }
  };

  const unblock = async (userId: string) => {
    setPending(true);
    try {
      await blockService.unblock(userId);
      setBlockedUsers((users) => users.filter((user) => user._id !== userId));
      toast.success("Đã huỷ chặn người dùng.");
    } catch (error) {
      toast.error(apiError(error, "Không thể huỷ chặn."));
    } finally {
      setPending(false);
    }
  };

  return (
    <Card className="glass-strong border-border/30">
      <CardHeader>
        <CardTitle className="flex items-center gap-2"><Shield className="size-5 text-primary" />Quyền riêng tư & Bảo mật</CardTitle>
        <CardDescription>Quản lý mật khẩu, thông báo và người dùng đã chặn</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {isGoogleAccount ? (
          <div className="rounded-xl border bg-muted/50 p-4 text-sm text-muted-foreground">
            Tài khoản này đăng nhập bằng Google và không có mật khẩu FlowChat. Hãy quản lý hoặc khôi phục mật khẩu tại{" "}
            <a className="font-medium text-primary underline" href="https://accounts.google.com/signin/recovery" target="_blank" rel="noreferrer">Tài khoản Google</a>.
          </div>
        ) : (
          <Button variant="outline" className="w-full justify-start" onClick={() => setPasswordOpen((open) => !open)}><Shield className="mr-2 size-4" />Đổi mật khẩu</Button>
        )}
        {passwordOpen && !isGoogleAccount && (
          <div className="space-y-3 rounded-xl border p-4">
            <div><Label htmlFor="current-password">Mật khẩu hiện tại</Label><Input id="current-password" type="password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} /></div>
            <div><Label htmlFor="new-password">Mật khẩu mới</Label><Input id="new-password" type="password" minLength={8} value={newPassword} onChange={(event) => setNewPassword(event.target.value)} /></div>
            <div><Label htmlFor="confirm-password">Xác nhận mật khẩu mới</Label><Input id="confirm-password" type="password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} /></div>
            <Button disabled={pending || newPassword.length < 8} onClick={() => void changePassword()}>{pending && <Loader2 className="animate-spin" />}Lưu mật khẩu</Button>
          </div>
        )}
        <Button variant="outline" className="w-full justify-start" onClick={() => toast.info("Bạn có thể bật hoặc tắt thông báo trong tab Cấu Hình.")}><Bell className="mr-2 size-4" />Cài đặt thông báo</Button>
        <Button variant="outline" className="w-full justify-start" onClick={() => void openBlocks()}><ShieldBan className="mr-2 size-4" />Người dùng đã chặn</Button>
        {blocksOpen && (
          <div className="space-y-2 rounded-xl border p-3">
            {pending && blockedUsers.length === 0 ? <Loader2 className="mx-auto animate-spin" /> : blockedUsers.length === 0 ? <p className="text-center text-sm text-muted-foreground">Bạn chưa chặn người dùng nào.</p> : blockedUsers.map((user) => (
              <div key={user._id} className="flex items-center gap-3 rounded-lg bg-muted/50 p-2">
                <UserAvatar type="sidebar" name={user.displayName} avatarUrl={user.avatarUrl} />
                <div className="min-w-0 flex-1"><p className="truncate font-medium">{user.displayName}</p><p className="truncate text-xs text-muted-foreground">@{user.username}</p></div>
                <Button size="sm" variant="outline" disabled={pending} onClick={() => void unblock(user._id)}>Huỷ chặn</Button>
              </div>
            ))}
          </div>
        )}
        <div className="border-t pt-4">
          <p className="mb-2 text-sm text-destructive">Khu vực nguy hiểm</p>
          <Button variant="destructive" className="w-full" disabled title="Tạm khóa để tránh xóa nhầm dữ liệu trò chuyện">Xoá tài khoản</Button>
          <p className="mt-2 text-xs text-muted-foreground">Chức năng xóa đang được khóa an toàn để không làm mất dữ liệu trò chuyện của bạn.</p>
        </div>
      </CardContent>
    </Card>
  );
};

export default PrivacySettings;
