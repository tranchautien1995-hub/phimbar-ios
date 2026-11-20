# Kiểm tra XemPhim iOS — 21/11/2026

## Phạm vi

App iOS viết mới từ hành vi/DTO/palette của APK người dùng cung cấp. Chưa có tài khoản dịch vụ hoặc iPhone XS Max iOS 15.1 được kết nối để kiểm tra phiên xem thật. Không thực hiện mua VIP, gia hạn, đăng nhập tài khoản người dùng hoặc thay đổi lịch sử phim thật.

## GitHub Actions

Lượt kiểm tra tích hợp ban đầu: [44813553589](https://github.com/tranchautien1995-hub/phimbar-ios/actions/runs/44813553589), commit b66b2bf615f81a91edcc73da4572d7abfca6a0e9.

- Swift protocol tests đạt: trường metadata, ID episode encoding, chỉ HTTPS/no credential URL, chuyển tên HLS, giữ query signed URL, SRT/VTT/ASS, AES-GCM round-trip và lỗi xác thực, đồng hồ resume.
- Build release arm64 deployment target iOS 15.0 thành công, ký ad-hoc, verify codesign; đóng gói Payload/XemPhim.app.
- Build simulator, khởi động app thật và chụp login/home/details/player. Fixture metadata chỉ biên dịch với `UI_PREVIEW` vào app simulator; không có trong IPA release.
- Trình phát dùng HLS mẫu Big Buck Bunny của test-streams.mux.dev, fixture API nội bộ trả mốc 40 giây và một cue tiếng Việt tổng hợp. Kết quả runtime: ready=true, playing=true, savedStart=40, position=41.000064063, subtitleRendered=true, cueCount=1. Screenshot xác nhận khung hình video và câu phụ đề nhìn thấy.
- Phim mẫu và câu phụ đề là dữ liệu kiểm tra, không phải xác nhận nội dung hoặc phụ đề của tài khoản Phimbar thật.

## Các giới hạn còn lại

Simulator dùng runtime iOS có sẵn trên runner macOS, không phải thiết bị XS Max/iOS 15.1 thật. Compilation target iOS 15.0 kiểm tra tính sẵn có của API, không chứng minh mọi codec/CDN hoặc entitlement trên thiết bị thật. Chưa thử đăng nhập hoàn chỉnh, play phim cần VIP, PiP thực, hoặc kiểm tra hình/tiếng trên iPhone của người dùng. Chỉ luồng cấp mã thiết bị API thật đã được kiểm tra không đăng nhập (200 đúng schema).

API TV của APK mẫu giới hạn VIP trọn gói/VIP tháng, không dùng thuê lẻ. App iOS giữ giới hạn máy chủ này; không tự mua hoặc thay đổi gói.
