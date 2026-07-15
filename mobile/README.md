# FlowChat Mobile

Ứng dụng Flutter sử dụng trực tiếp REST API trong `../backend`. Mobile hiện có:

- đăng ký, đăng nhập, tự làm mới access token và đăng xuất;
- danh sách hội thoại direct/group, unread và đồng bộ định kỳ;
- phân trang, gửi tin nhắn text và mark-as-seen;
- tạo hội thoại trực tiếp hoặc nhóm;
- danh sách bạn bè, tìm username, gửi/chấp nhận/từ chối lời mời;
- hồ sơ, upload avatar tối đa 1 MB và light/dark mode.
- gọi thoại WebRTC 1–1 giữa mobile và web khi hai ứng dụng đang mở.
- đăng nhập hoặc đăng ký bằng tài khoản Google qua backend FlowChat.

Không có migration, seed hay lệnh reset database trong quy trình chạy mobile.

## 1. Chạy backend

Giữ nguyên `MONGODB_CONNECTIONSTRING` hiện tại của bạn; không sao chép đè `.env` nếu file này đã được cấu hình.

```bash
cd /home/quang02092005/Project_DACN/FlowChat/backend
npm install
npm run dev
```

Backend mặc định chạy ở cổng `5001`. Có thể kiểm tra Swagger tại:

```text
http://localhost:5001/api-docs
```

## 2. Cài dependency Flutter

```bash
cd /home/quang02092005/Project_DACN/FlowChat/mobile
flutter pub get
flutter devices
```

Nếu lệnh `flutter` chưa nằm trong `PATH`, dùng binary của máy này:

```bash
/home/quang02092005/SDKFlutter/flutter/bin/flutter pub get
```

## 3. Chạy ứng dụng

### Cấu hình Google Sign-In (Android)

Trong cùng Google Cloud project với web:

1. Tạo OAuth Client ID loại **Android**, package name là `com.flowchat.mobile`.
2. Điền SHA-1 của debug keystore. Có thể xem bằng:

```bash
cd android
./gradlew signingReport
```

3. Tạo hoặc dùng OAuth Client ID loại **Web application**. Điền ID này vào
   `GOOGLE_CLIENT_IDS` của `backend/.env` và truyền cho Flutter bằng
   `GOOGLE_WEB_CLIENT_ID`. Không truyền Android Client ID vào tham số này.

Android không cần chép `google-services.json` vì ứng dụng truyền trực tiếp Web
Client ID làm `serverClientId`.

### Android Emulator

Android Emulator truy cập máy host bằng `10.0.2.2`, không phải `localhost`:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:5001/api \
  --dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

Đây cũng là base URL mặc định, nên trong Android Emulator có thể chạy ngắn gọn:

```bash
flutter run
```

### Điện thoại Android thật

Điện thoại và máy chạy backend phải cùng mạng Wi-Fi. Lấy IPv4 LAN của máy tính, ví dụ `192.168.1.20`, rồi chạy:

```bash
flutter run -d <device-id> \
  --dart-define=API_BASE_URL=http://192.168.1.20:5001/api \
  --dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

Đảm bảo firewall cho phép kết nối TCP tới cổng `5001`. Không dùng `127.0.0.1` hoặc `localhost`, vì hai địa chỉ đó trỏ về chính điện thoại.

### iOS Simulator

Lệnh này phải chạy trên macOS có Xcode:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://127.0.0.1:5001/api
```

### Backend production

Cấu hình production đang được frontend hiện tại sử dụng:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://moji-realtimechatapp-backend.onrender.com/api
```

Ứng dụng release nên luôn gọi backend HTTPS.

### Cấu hình TURN cho gọi qua Internet

Development có sẵn STUN mặc định. Khi hai thiết bị ở mạng khác nhau, production nên cấu hình TURN:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://api.example.com/api \
  --dart-define=WEBRTC_STUN_URL=stun:stun.l.google.com:19302 \
  --dart-define=WEBRTC_TURN_URL=turns:turn.example.com:5349 \
  --dart-define=WEBRTC_TURN_USERNAME=your-username \
  --dart-define=WEBRTC_TURN_CREDENTIAL=your-credential
```

Không commit credential TURN thật. Bản production nên dùng credential ngắn hạn. Cuộc gọi hiện nhận được khi ứng dụng đang mở; nhận cuộc gọi khi app bị tắt cần triển khai thêm FCM/APNs và CallKit/ConnectionService.

## 4. Chạy kiểm tra và build APK

```bash
flutter analyze
flutter test
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://10.0.2.2:5001/api \
  --dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

APK debug nằm tại:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Lỗi thường gặp

- `Connection refused`: backend chưa chạy, sai IP/cổng hoặc firewall đang chặn.
- Android Emulator không kết nối được `localhost`: đổi thành `10.0.2.2`.
- Điện thoại thật không kết nối: dùng IPv4 LAN của máy tính và kiểm tra hai thiết bị cùng Wi-Fi.
- Backend báo thiếu biến môi trường: kiểm tra `.env` có MongoDB, access-token secret và Cloudinary; không thay/xóa connection string đang dùng.
- Avatar không tải lên: ảnh phải không quá 1 MB và Cloudinary phải được cấu hình đúng.
- Sau khi đổi base URL: dừng ứng dụng và chạy lại với `--dart-define`; hot reload không thay compile-time define.
- Google báo `ApiException: 10` hoặc `clientConfigurationError`: kiểm tra package `com.flowchat.mobile`, SHA-1 của đúng keystore và Web Client ID truyền qua `--dart-define`.
- Web không có nút gọi: chỉ hội thoại direct hỗ trợ gọi và backend mới phải đang chạy.
- Gọi được nhưng không có âm thanh giữa hai mạng khác nhau: cấu hình TURN cho cả web và mobile.
