# XemPhim iOS 1.1.2 — trình phát iOS toàn màn hình

Nút Toàn màn hình iOS trình bày trực tiếp AVPlayerViewController, dùng chung AVPlayer và current item. Giữ video và mốc đang xem khi chuyển vào/ra; chặn cleanup của màn phát nền trong lúc native player mở; khôi phục AVPlayerLayer khi quay lại. Phụ đề ngoài hiển thị bằng contentOverlayView không nhận thao tác chạm. Các tùy chọn CC vẫn nằm ở màn phát của app.

Kiểm tra chạm thực trên simulator đã đạt cho hiện điều khiển, phát/dừng và nút Close quay về màn phát. Kiểm tra seek tới 75 giây bằng AVPlayer đã đạt; thanh thời gian native được kiểm tra bằng ảnh, chưa xác nhận kéo timeline bằng bài test chạm. Không coi phép thử chỉnh âm lượng trong log UI cũ là bằng chứng tua video. Chưa chạy trên XS Max iOS 15.1 thật.

Giữ giao diện, danh mục, tìm kiếm, thư viện, trình phát và Keychain của bản 1.0.0 đã giao. Thêm nút Thuê lẻ phim này / Thuê tập cho từng tập; thêm màn thuê website ngay trong app. Bundle ID giữ nguyên để cài cập nhật, không xóa dữ liệu.

## Cách dùng

Chọn phim/tập → Thuê lẻ → đăng nhập Phimbar trong khung web nếu cần → Thuê tập này → chọn thuê lẻ trên website → xem xác nhận tên phim/tập, giá và thời hạn → Xác nhận thuê. Giá lấy từ website, không hardcode. Chỉ sau khi người dùng xác nhận mới bấm đúng nút thuê lẻ gốc. Bấm Phát tập đã thuê khi website đã có video; nếu cần, bấm phát trên website trước để trang tải nguồn và phụ đề.

Luồng mua không bấm gói tháng. Gói tháng bị ẩn/chặn trong màn thuê; giá/tập thay đổi sẽ hủy xác nhận cũ; chặn gửi lại cùng giao dịch. App không thay đổi giá hoặc quyền VIP trên máy chủ.

Website có phiên đăng nhập riêng; xác nhận thanh toán áp dụng cho tài khoản đang đăng nhập trên website. App không gửi token API TV sang website/CDN. Không tự mua, không tự gia hạn và không tự chọn gói tháng.

## Phát nội dung đã có quyền

Giữ luồng API TV hiện có. Khi máy chủ từ chối video, app mở luồng thuê website chính thức. Phát nguồn mà website đã cấp cho trình phát HTML/Video.js; không giả mạo quyền xem hoặc bỏ kiểm tra của máy chủ. Màn mua yêu cầu đăng nhập và quyền thuê thực.

Native AVPlayer/AVPlayerLayer, điều khiển, CC và PiP giữ như bản trước. Adapter HLS chỉ lắng nghe 127.0.0.1, dùng nonce mỗi phiên, tải nguồn HTTPS và chuyển URI playlist/segment về đường tương thích. Cookie website chỉ dùng đúng host của website, được gỡ khi redirect sang CDN; không gửi API bearer token cho host video.

Phụ đề từ TextTrack website được chuyển sang CC. Nếu phụ đề chưa tải, chọn sub/phát trên website trước rồi chuyển sang app. Đổi máy chủ của nguồn thuê lẻ đi qua màn website. Vị trí nguồn web lưu cục bộ để không gửi tiến độ bằng tài khoản API khác với phiên website. Thư viện và tiến độ API TV giữ luồng cũ.

## Kiểm tra và build

Build GitHub Actions trên nhánh codex/xemphim-episode-rental, arm64/iOS 15.0, ký ad-hoc với cùng identity Keychain. Nguồn tham chiếu là bản 1.0.0 commit 85075bc4ffc68682efc74b81a3f3e8048e4c873a.

Tests/rental.test.cjs kiểm tra không tự mua khi mở, xác nhận đúng rental một lần, chặn gói tháng, đổi giá/tập phải xác nhận lại, không tạo nguồn khi website chưa cấp video. Các test dùng DOM tổng hợp, không nối giao dịch thật. Protocol tests kiểm tra HLS URI, cookie scope và phụ đề. Simulator kiểm tra cả player API mẫu và player nguồn web qua adapter; đều là video/phụ đề mẫu không liên quan tài khoản thật.

Không thực hiện giao dịch thật hoặc thử tài khoản người dùng khi build. Chưa xác nhận luồng trừ tiền/thuê lẻ trên iPhone XS Max iOS 15.1 thật. API web và bố cục website có thể đổi; nếu website chưa cấp nguồn, app báo lỗi và không tuyên bố đã mua hoặc đã có quyền xem. CSS tương thích iOS 15 tái sử dụng từ bản Phimbar iOS trước, nguồn stylesheet bất biến 2.bidTnhBZ.css.
