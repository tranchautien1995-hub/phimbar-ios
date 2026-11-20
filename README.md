# XemPhim cho iOS 15 / TrollStore

Bản iOS viết lại bằng SwiftUI/AVKit, tham chiếu APK `XemPhim-v1.4.apk` do người dùng cung cấp. Giữ bảng màu Navy `#091224`, Surface `#182135`, Accent `#E50914`, menu Trang chủ / Series / Phim / Tìm kiếm / Danh sách của tôi / Tài khoản và các hàng poster. APK gốc là giao diện Android TV; bản iOS chuyển điều khiển sang cảm ứng và co bố cục theo màn hình iPhone/iPad. Không phải chuyển đổi nhị phân APK sang IPA hoặc bản được nhà cung cấp xác nhận.

## Chức năng

- Đăng nhập email/mật khẩu hoặc mã thiết bị; API gốc `https://phimfly.com/api/tv/v1/`, cùng wire contract của APK. Tài khoản đăng nhập trực tiếp trong app; mật khẩu không được lưu. Phiên lưu Keychain WhenUnlockedThisDeviceOnly trong access group riêng `TROLLTROLL.vn.onnstream.phimbar.ios`, không ghi log token. Chữ ký ad-hoc kèm application-identifier/team/keychain group thông thường, không xin quyền hệ thống.
- Trang chủ từ `home`, Thịnh hành Ngày/Tuần/Tháng khi API có trả ranges; danh mục Series/Phim với bộ lọc và phân trang; tìm kiếm có debounce/hủy truy vấn cũ; các danh sách updates/watching/wishlist/watched; xem số dư và VIP.
- Chi tiết phim, mùa/tập, danh sách cá nhân. Trình phát AVPlayer/AVPlayerLayer với nút phát, thanh thời gian và CC riêng: tua, chọn máy chủ 1/2/3, tốc độ, phụ đề tích hợp iOS, PiP nếu nguồn và hệ thống hỗ trợ; tập tiếp khi API trả về.
- Phụ đề ngoài SRT/WebVTT/ASS, định dạng payload của API gốc, chọn bản dịch, likes/dislikes, cỡ chữ/vị trí/nền đen/chữ vàng/lệch thời gian. ASS hiển thị lời thoại cơ bản, không tái tạo mọi hiệu ứng karaoke/typesetting của Android.
- Đọc mốc xem server; lưu tiến độ khi đã phát được video, không ghi số 0 từ lỗi tải. Có fallback vị trí cục bộ. Chọn phụ đề không tạo lại AVPlayerItem và không đổi vị trí video.
- HTTPS; token API không gửi tới máy chủ video hoặc ảnh. Kiểm tra watching-elsewhere khi đang phát để xử lý phiên xem trên thiết bị khác. Không có endpoint mua tự động, không mua/gia hạn VIP, không thay đổi quyền tài khoản.

## Giới hạn từ app mẫu

APK gốc có thông báo yêu cầu VIP trọn gói/VIP tháng còn hạn, thuê lẻ từng phim không áp dụng trên TV. Bản này dùng cùng API TV và không loại bỏ giới hạn đó. Phát được hay không còn phụ thuộc quyền tài khoản, codec iOS và tình trạng máy chủ. Không hứa giao diện trùng từng pixel giữa Android TV và iPhone.

Nút quản lý tài khoản mở website gốc trong trình duyệt iOS; phần web này vẫn có thể gặp hạn chế iOS 15. Danh mục và trình phát chính dùng giao diện iOS trực tiếp.

## Build

GitHub Actions `Build XemPhim iOS IPA`, macOS, target `arm64-apple-ios15.0`, không cần chứng chỉ Apple trả phí. Chạy kiểm tra protocol/crypto/phụ đề, build và ký ad-hoc IPA, build simulator và chụp màn đăng nhập. Artifact `XemPhim-iOS15-TrollStore` chứa IPA, SHA256 và ảnh kiểm tra. Cài IPA bằng TrollStore.

Bundle ID `vn.onnstream.phimbar.ios` giữ như bản Phimbar iOS trước; cập nhật thay giao diện app đó, không liên quan MessengerRestart hoặc OnnStream trên TV. Không yêu cầu entitlement đặc quyền.

## Tham chiếu và kiểm tra

- SHA256 APK người dùng cung cấp: `bc09b4e545a2b6092bc861faa5a9b1b170ec3a021d70defd705da2dc1bff4340`.
- Phân tích tĩnh manifest, nhãn menu, màu, API/DTO, biến đổi URL HLS và định dạng phụ đề; không đưa APK, mã Android dịch ngược, cookie, token hoặc tài khoản lên GitHub.
- Lượt kiểm tra API công khai 21/11/2026: API yêu cầu xác thực (401); cấp mã thiết bị trả 200 đúng trường code/pollToken/expiresInSeconds/intervalSeconds. Không có tài khoản được đăng nhập trong lượt này.
- Test protocol dùng dữ liệu tổng hợp, không dùng tài khoản hoặc phim trả phí. Build/simulator không chứng minh đã phát phim tài khoản thật trên iPhone XS Max iOS 15.1; cần kiểm tra thiết bị đó sau khi cài.

Lớp video dùng AVPlayerLayer nằm trong giới hạn view, để phần điều khiển và phụ đề ngoài không bị giao diện toàn màn hình tự động của AVPlayerViewController che. Phụ đề ngoài nằm trên màn hình phát chính; PiP dùng các track mà AVPlayer hỗ trợ trực tiếp.
