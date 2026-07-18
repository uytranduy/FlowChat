import { Sun, Moon } from "lucide-react";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { useThemeStore } from "@/stores/useThemeStore";
import { useState } from "react";
import { useAuthStore } from "@/stores/useAuthStore";
import { userService } from "@/services/userService";
import { toast } from "sonner";

const PreferencesForm = () => {
  const { isDark, toggleTheme } = useThemeStore();
  const user = useAuthStore((state) => state.user);
  const setUser = useAuthStore((state) => state.setUser);
  const [saving, setSaving] = useState(false);

  const updatePreference = async (updates: { showOnlineStatus?: boolean; notificationsEnabled?: boolean }) => {
    if (!user || saving) return;
    setSaving(true);
    try {
      const updated = await userService.updatePreferences({
        showOnlineStatus: updates.showOnlineStatus ?? user.showOnlineStatus ?? true,
        notificationsEnabled: updates.notificationsEnabled ?? user.notificationsEnabled ?? true,
      });
      setUser(updated);
      toast.success("Đã lưu cấu hình.");
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể lưu cấu hình.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card className="glass-strong border-border/30">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Sun className="h-5 w-5 text-primary" />
          Tuỳ chỉnh ứng dụng
        </CardTitle>
        <CardDescription>Cá nhân hoá trải nghiệm trò chuyện của bạn</CardDescription>
      </CardHeader>

      <CardContent className="space-y-6">
        {/* Dark Mode */}
        <div className="flex items-center justify-between">
          <div>
            <Label
              htmlFor="theme-toggle"
              className="text-base font-medium"
            >
              Chế độ tối
            </Label>
            <p className="text-sm text-muted-foreground">
              Chuyển đổi giữa giao diện sáng và tối
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Sun className="h-4 w-4 text-muted-foreground" />
            <Switch
              id="theme-toggle"
              checked={isDark}
              onCheckedChange={toggleTheme}
              className="data-[state=checked]:bg-primary-glow"
            />
            <Moon className="h-4 w-4 text-muted-foreground" />
          </div>
        </div>

        {/* Online Status */}
        <div className="flex items-center justify-between">
          <div>
            <Label
              htmlFor="online-status"
              className="text-base font-medium"
            >
              Hiển thị trạng thái online
            </Label>
            <p className="text-sm text-muted-foreground">
              Cho phép người khác thấy khi bạn đang online
            </p>
          </div>
          <Switch
            id="online-status"
            checked={user?.showOnlineStatus ?? true}
            disabled={saving}
            onCheckedChange={(checked) => void updatePreference({ showOnlineStatus: checked })}
            className="data-[state=checked]:bg-primary-glow"
          />
        </div>

        <div className="flex items-center justify-between">
          <div>
            <Label htmlFor="notification-status" className="text-base font-medium">Thông báo</Label>
            <p className="text-sm text-muted-foreground">Hiển thị thông báo tin nhắn, cuộc gọi và lời mời kết bạn</p>
          </div>
          <Switch id="notification-status" checked={user?.notificationsEnabled ?? true} disabled={saving} onCheckedChange={(checked) => void updatePreference({ notificationsEnabled: checked })} />
        </div>
      </CardContent>
    </Card>
  );
};

export default PreferencesForm;
