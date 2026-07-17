# FlowChat Web

Frontend React/Vite của FlowChat, gồm chat realtime và gọi thoại WebRTC 1–1 với web hoặc ứng dụng Flutter.

## Chạy local

Chạy backend trước:

```bash
cd /home/quang02092005/Project_DACN/FlowChat/backend
npm install
npm run dev
```

Sau đó chạy web:

```bash
cd /home/quang02092005/Project_DACN/FlowChat/frontend
npm install
npm run dev
```

Cấu hình development hiện tại dùng:

```env
VITE_API_URL=http://localhost:5001/api
VITE_SOCKET_URL=http://localhost:5001/
VITE_GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

## Đăng nhập/đăng ký bằng Google

Trong Google Cloud Console, tạo OAuth 2.0 Client ID loại **Web application** và
thêm `http://localhost:5173` vào **Authorized JavaScript origins**. Dùng cùng
Web Client ID cho cả ba nơi sau:

```env
# backend/.env
GOOGLE_CLIENT_IDS=your-web-client-id.apps.googleusercontent.com

# frontend/.env.development
VITE_GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

Khởi động lại backend và frontend sau khi sửa biến môi trường. Backend luôn xác
minh Google ID token trước khi tạo tài khoản hoặc đăng nhập; frontend không tự
tin email/profile do trình duyệt gửi lên.

## Xác minh email và quên mật khẩu

FlowChat gửi liên kết xác minh khi đăng ký bằng email và liên kết đặt lại mật
khẩu có hiệu lực 30 phút. Với Gmail SMTP, bật xác minh 2 bước, tạo **Mật khẩu
ứng dụng**, rồi cấu hình `backend/.env`:

```env
APP_PUBLIC_URL=http://localhost:5173
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-16-character-app-password
SMTP_FROM="FlowChat <your-email@gmail.com>"
```

`SMTP_PASS` không phải mật khẩu Gmail thông thường và không được commit vào
Git. Trong production, `APP_PUBLIC_URL` phải là địa chỉ HTTPS công khai của web.
Tài khoản chỉ dùng Google không có mật khẩu FlowChat; việc khôi phục mật khẩu
được thực hiện tại Google.

Nút gọi chỉ xuất hiện trong hội thoại trực tiếp. Trình duyệt sẽ yêu cầu quyền microphone khi gọi hoặc nhận máy.

## STUN/TURN cho cuộc gọi

Development mặc định dùng STUN `stun:stun.l.google.com:19302`. Để gọi ổn định giữa Wi-Fi, 4G/5G hoặc các mạng NAT khác nhau, production cần TURN:

```env
VITE_WEBRTC_STUN_URL=stun:stun.l.google.com:19302
VITE_WEBRTC_TURN_URL=turns:turn.example.com:5349
VITE_WEBRTC_TURN_USERNAME=your-username
VITE_WEBRTC_TURN_CREDENTIAL=your-credential
```

Web production phải chạy HTTPS; trình duyệt không cấp microphone cho origin HTTP thông thường. Không commit credential TURN thật vào Git. Production nên cấp credential TURN ngắn hạn từ server tin cậy.

## Kiểm tra

```bash
npm run build
npm run lint
```

Cuộc gọi hiện hoạt động khi web/mobile đang mở và kết nối Socket.IO. Nhận cuộc gọi khi ứng dụng bị tắt hoặc bị hệ điều hành đóng nền cần tích hợp thêm FCM/APNs và CallKit/ConnectionService.
