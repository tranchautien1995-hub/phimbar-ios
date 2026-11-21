# XemPhim iOS 1.0.0 — bản giao 21/11/2026

Bản IPA và mã nguồn phát hành lấy từ commit 85075bc4ffc68682efc74b81a3f3e8048e4c873a. Build và kiểm tra: https://github.com/tranchautien1995-hub/phimbar-ios/actions/runs/44819312373 . Artifact 14672296678. Thư mục nguồn phát hành: work/XemPhimIOS-release-1.0.0; không dùng bản refactor mới hơn để mô tả IPA này.

- 13 kiểm tra protocol đạt: metadata, mã tập, HTTPS, URL HLS, giữ query signed URL, ranges thịnh hành, SRT/VTT/ASS, AES-GCM, xử lý payload sai và mốc thời gian.
- Build arm64 deployment target iOS 15.0 và xác minh chữ ký ad-hoc thành công. Keychain giới hạn trong group riêng của app; không xin quyền hệ thống.
- Simulator/Xcode QA: savedAndRead=true, deleted=true. Không phải đăng nhập tài khoản dịch vụ thật; token QA được xóa trong phép thử.
- Player mẫu HLS: ready=true, playing=true, savedStart=40, position=41.000064596, subtitleRendered=true, cueCount=1. Dữ liệu phim và phụ đề dùng để thử, không phải dữ liệu từ tài khoản Phimbar.
- Đã xem ảnh simulator-player.png: thấy khung hình video, câu phụ đề tiếng Việt, nút đóng/tên phim, phát-tạm dừng, thanh thời gian, tua 15s, máy chủ, CC và PiP. Lớp AVPlayerLayer giữ video trong view, điều khiển/sub không bị giao diện AVPlayerViewController che.
- IPA 442571 bytes; SHA256 7b940c887eb192b8fe5fc529b7dd98fa45dcfcfcea0b2515bec080babc9a3c88, khớp file SHA256 của GitHub.

Chưa kiểm tra trên iPhone XS Max iOS 15.1 thật, chưa đăng nhập tài khoản VIP thật hoặc thực hiện giao dịch. PiP thực, codec/CDN của mọi phim và đồng bộ tiến độ tài khoản thật chưa được xác nhận. ASS hỗ trợ lời thoại cơ bản, không mọi hiệu ứng typesetting. API TV của APK mẫu yêu cầu VIP trọn gói/VIP tháng; thuê lẻ không áp dụng. Giao diện được dựng lại cho cảm ứng iPhone, không xác nhận trùng từng pixel với Android TV.

Phân tích APK tham chiếu SHA256 bc09b4e545a2b6092bc861faa5a9b1b170ec3a021d70defd705da2dc1bff4340. Không tải APK, mã Android dịch ngược, tài khoản, cookie hoặc token thật lên GitHub. Không mua/gia hạn VIP và không sửa dữ liệu xem thật trong lúc thử.
