# XemPhim iOS 1.1.0 — kiểm tra bản cập nhật thuê lẻ

Bản cập nhật dựa trên bản phát hành 1.0.0 commit 85075bc4ffc68682efc74b81a3f3e8048e4c873a, giữ bundle ID và Keychain group. Không dùng bản refactor thử nghiệm làm nền.

8 kiểm tra thuê lẻ bằng DOM tổng hợp: mở modal đồng bộ/bất đồng bộ không tự mua và ẩn gói tháng; bấm thuê cần xác nhận; xác nhận đúng một lần; giá/tập thay đổi làm xác nhận cũ vô hiệu; chặn click/submit gói tháng; trang đăng nhập không tạo giao dịch; không tự tạo URL phát.

18 kiểm tra protocol/subtitle/HLS được chạy trên GitHub. Simulator chạy Keychain save/read/delete, phát HLS mẫu theo luồng API cũ và luồng website qua adapter nội bộ, phụ đề mẫu và vị trí tiếp tục xem. Xem artifact của lần build tương ứng để có kết quả thực tế; không coi mô tả phép thử là bằng chứng đạt.

Không đăng nhập tài khoản thật hoặc thực hiện giao dịch thật trong các phép thử. Chưa kiểm tra thanh toán thuê lẻ, mọi codec/CDN hoặc trên iPhone XS Max iOS 15.1 thật. API và bố cục website có thể thay đổi. App chỉ phát URL mà website cấp sau khi kiểm tra quyền; không thay giá/quyền VIP trên máy chủ. Phiên website riêng với API TV; tiến độ nguồn web chỉ lưu cục bộ.

Không đưa APK tham chiếu, mã Android dịch ngược, mật khẩu, token hay cookie thật lên GitHub. Entitlements giữ phạm vi app và Keychain riêng, không xin quyền hệ thống.
