export function presenceText({
  isOnline,
  lastSeenAt,
  presenceVisible = true,
  now = Date.now(),
}: {
  isOnline: boolean;
  lastSeenAt?: string | null;
  presenceVisible?: boolean;
  now?: number;
}): string {
  if (!presenceVisible) return "Không hiển thị trạng thái hoạt động";
  if (isOnline) return "Đang hoạt động";
  if (!lastSeenAt) return "Không hoạt động";

  const lastSeen = new Date(lastSeenAt).getTime();
  if (!Number.isFinite(lastSeen)) return "Không hoạt động";
  const minutes = Math.max(0, Math.floor((now - lastSeen) / 60_000));
  if (minutes < 1) return "Hoạt động vừa xong";
  if (minutes < 60) return `Hoạt động ${minutes} phút trước`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `Hoạt động ${hours} giờ trước`;
  return `Hoạt động ${Math.floor(hours / 24)} ngày trước`;
}
