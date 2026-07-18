String presenceText({
  required bool isOnline,
  DateTime? lastSeenAt,
  bool presenceVisible = true,
  DateTime? now,
}) {
  if (!presenceVisible) return 'Không hiển thị trạng thái hoạt động';
  if (isOnline) return 'Đang hoạt động';
  if (lastSeenAt == null) return 'Không hoạt động';
  final minutes = (now ?? DateTime.now())
      .difference(lastSeenAt.toLocal())
      .inMinutes;
  if (minutes < 1) return 'Hoạt động vừa xong';
  if (minutes < 60) return 'Hoạt động $minutes phút trước';
  final hours = minutes ~/ 60;
  if (hours < 24) return 'Hoạt động $hours giờ trước';
  return 'Hoạt động ${hours ~/ 24} ngày trước';
}
