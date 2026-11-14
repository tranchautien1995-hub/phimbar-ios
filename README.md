# Phimbar cho iOS 15 — bản thử nghiệm

App arm64 cho iPhone XS Max iOS 15.1, WKWebView và polyfill Array.at/String.at/Object.hasOwn. Cookies lưu trong app; đăng nhập trực tiếp trên Phimbar. Không có API key, tài khoản hoặc dữ liệu OnnStream Android trong repo. Quyền VIP/thanh toán do trang gốc xử lý, app không tự mua.

0.1.1: chuyển stylesheet đầy đủ của Phimbar sang CSS cho iOS 15 bằng PostCSS Preset Env. Loại bỏ cascade layers, hạ cú pháp media query và màu, khởi tạo biến thay @property. Bỏ các quy tắc nút/kích thước chung gây chồng giao diện ở 0.1.0. Nguồn CSS công khai được khóa URL/hash; dependency được khóa bằng package-lock.json. Chạy npm ci rồi node scripts/prepare-css.mjs trước khi build; GitHub Actions thực hiện tự động. Resources/legacy.css là file sinh ra, không sửa bằng tay.

GitHub Actions dùng macOS/Xcode tạo app iOS deployment target 15.0, ký ad-hoc rồi nén đúng Payload/Phimbar.app. Tải artifact Phimbar-iOS15-TrollStore, giải nén IPA, mở trong TrollStore. Không phải IPA ký App Store.

Đây là bản sửa giao diện thử nghiệm, chưa được xác nhận trên máy iOS 15.1 thực. WKWebView vẫn dùng WebKit của iOS; app không nâng cấp engine và không bảo đảm sửa mọi lỗi JavaScript/CSS hiện đại của dịch vụ. Cần thử đăng nhập, danh mục, phim và VIP. Tùy chọn cho phép áp lại CSS hoặc xem giao diện gốc. Không thêm entitlement đặc quyền, không đòi mật khẩu Apple ID.
