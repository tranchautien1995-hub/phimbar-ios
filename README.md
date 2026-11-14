# Phimbar cho iOS 15 — bản thử nghiệm

App arm64 cho iPhone XS Max iOS 15.1, WKWebView + lớp CSS tương thích cơ bản, polyfill Array.at/String.at/Object.hasOwn. Cookies lưu trong app; đăng nhập trực tiếp trên Phimbar. Không có API key, tài khoản hoặc dữ liệu OnnStream Android trong repo. Quyền VIP/thanh toán do trang gốc xử lý, app không tự mua.

GitHub Actions dùng macOS/Xcode tạo app iOS deployment target 15.0, ký ad-hoc rồi nén đúng Payload/Phimbar.app. Tải artifact Phimbar-iOS15-TrollStore, giải nén IPA, mở trong TrollStore. Không phải IPA ký App Store.

Đây là bản sửa giao diện thử nghiệm, chưa được xác nhận trên máy iOS 15.1 thực. WKWebView vẫn dùng WebKit của iOS; app không nâng cấp engine và không bảo đảm sửa mọi lỗi JavaScript/CSS hiện đại của dịch vụ. Cần thử đăng nhập, danh mục, phim và VIP. Tùy chọn cho phép áp lại CSS hoặc xem giao diện gốc. Không thêm entitlement đặc quyền, không đòi mật khẩu Apple ID.
