import { Heart } from "lucide-react";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import type { User } from "@/types/user";
import { useEffect, useState } from "react";
import { userService } from "@/services/userService";
import { useAuthStore } from "@/stores/useAuthStore";
import { useChatStore } from "@/stores/useChatStore";
import { toast } from "sonner";

type EditableField = {
  key: keyof Pick<User, "displayName" | "username" | "email" | "phone">;
  label: string;
  type?: string;
};

const PERSONAL_FIELDS: EditableField[] = [
  { key: "displayName", label: "Tên hiển thị" },
  { key: "username", label: "Tên người dùng" },
  { key: "email", label: "Email", type: "email" },
  { key: "phone", label: "Số điện thoại" },
];

type Props = {
  userInfo: User | null;
};

const PersonalInfoForm = ({ userInfo }: Props) => {
  const setUser = useAuthStore((state) => state.setUser);
  const [form, setForm] = useState({ displayName: "", username: "", email: "", phone: "", bio: "" });
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!userInfo) return;
    setForm({
      displayName: userInfo.displayName,
      username: userInfo.username,
      email: userInfo.email,
      phone: userInfo.phone ?? "",
      bio: userInfo.bio ?? "",
    });
  }, [userInfo]);

  if (!userInfo) return null;

  const save = async () => {
    if (saving) return;
    setSaving(true);
    try {
      const user = await userService.updateProfile(form);
      setUser(user);
      await useChatStore.getState().fetchConversations();
      toast.success("Đã lưu thông tin cá nhân.");
    } catch (error) {
      toast.error((error as { response?: { data?: { message?: string } } }).response?.data?.message || "Không thể cập nhật hồ sơ.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card className="glass-strong border-border/30">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Heart className="size-5 text-primary" />
          Thông tin cá nhân
        </CardTitle>
        <CardDescription>
          Cập nhật chi tiết cá nhân và thông tin hồ sơ của bạn
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {PERSONAL_FIELDS.map(({ key, label, type }) => (
            <div
              key={key}
              className="space-y-2"
            >
              <Label htmlFor={key}>{label}</Label>
              <Input
                id={key}
                type={type ?? "text"}
                value={form[key]}
                onChange={(event) => setForm((current) => ({ ...current, [key]: event.target.value }))}
                className="glass-light border-border/30"
              />
            </div>
          ))}
        </div>

        <div className="space-y-2">
          <Label htmlFor="bio">Giới thiệu</Label>
          <Textarea
            id="bio"
            rows={3}
            value={form.bio}
            maxLength={500}
            onChange={(event) => setForm((current) => ({ ...current, bio: event.target.value }))}
            className="glass-light border-border/30 resize-none"
          />
        </div>

        <Button disabled={saving} onClick={() => void save()} className="w-full md:w-auto bg-gradient-primary hover:opacity-90 transition-opacity">
          {saving ? "Đang lưu..." : "Lưu thay đổi"}
        </Button>
      </CardContent>
    </Card>
  );
};

export default PersonalInfoForm;
