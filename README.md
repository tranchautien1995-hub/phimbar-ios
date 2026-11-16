# Mở lại Mess — TrollStore / iOS 15

0.2.0: chạm biểu tượng để bật chế độ tự động, chạm lại để tắt. Khi bật, yêu cầu quyền chạy nền đặc biệt của TrollStore trước; chỉ khi nhận được quyền mới mở lại Messenger và đặt chu kỳ 30 giây. Không có menu hay bước xác nhận trong luồng bình thường. Đây là cách đóng/mở lại Messenger (`com.facebook.Messenger`), không sửa lỗi đồng bộ của Meta.

Bộ hẹn giờ dùng thời gian đơn điệu; chu kỳ quá hạn chỉ chạy một lần, không chạy dồn. Bỏ qua chu kỳ khi khóa máy hoặc CallKit báo cuộc gọi chưa kết thúc. Đây không phải cơ chế nhận biết mọi cuộc gọi của mọi app; bản thử nghiệm vẫn có thể ngắt việc đang gõ/gửi. Mở Messenger định kỳ có thể kéo Messenger lên trước app khác. Ngừng ngay khi quyền nền mất, đóng/mở bị từ chối hoặc chờ quá lâu. Tắt tiện ích trong đa nhiệm/khởi động lại máy sẽ ngừng chế độ tự động; trạng thái bật không lưu qua lần app bị kết thúc. Khi tắt, callback cũ bị vô hiệu hóa để tránh tiếp tục mở Messenger.

Chỉ dùng trên thiết bị cá nhân có TrollStore. Bản thử nghiệm arm64, deployment target iOS 15.0, cần thử trên iPhone XS Max iOS 15.1. Build thành công không xác nhận quyền riêng hoạt động trên thiết bị thực. Nếu bị từ chối hoặc hết thời gian chờ, app hiện lỗi và không tuyên bố đã khởi động lại thành công.

App chỉ yêu cầu đóng/mở đúng bundle ID cố định; không có API mạng, tài khoản, đọc tin nhắn hay thao tác xóa dữ liệu. Việc đóng Messenger có thể ngắt cuộc gọi hoặc nội dung đang gửi như vuốt tắt app.

Quyền: platform-application, no-sandbox/container-required=false, multitasking.termination, multitasking.unlimitedassertions/systemappassertions và quyền launchapplications của FrontBoard/BackBoard/SpringBoard. Không thêm quyền unsigned-code/JIT bị cấm trên A12+ iOS 15. BKSProcessAssertion chỉ trỏ tới PID của chính tiện ích, flags=PreventTaskSuspend|AllowIdleSleep, reason=FinishTaskUnbounded. Không phát âm thanh im lặng để giả hoạt động nền. Các API riêng được tra cứu lúc chạy và kiểm tra selector trước khi gọi. Các quyền rộng thuộc cơ chế TrollStore, không giới hạn được ở riêng Messenger bằng entitlement; giới hạn bundle ID nằm trong mã nguồn.

Tham khảo chữ ký API và entitlement từ [TrollStore](https://github.com/opa334/TrollStore/tree/main/RootHelper) và [runtime header FBSSystemService](https://github.com/JaviSoto/iOS10-Runtime-Headers/blob/master/PrivateFrameworks/FrontBoardServices.framework/FBSSystemService.h). Không tích hợp mã nguồn của TrollStore.

GitHub Actions chạy kiểm tra bộ lập lịch (đúng hạn, bỏ qua cuộc gọi/khóa, dừng, bật lại, callback trễ), dùng macOS SDK biên dịch, tạo biểu tượng, ký ad-hoc kèm entitlement và đóng gói IPA. Cài bằng TrollStore; sau đó chạm biểu tượng “Mở lại Mess”. Không thể cam kết iOS 15.1 thực sẽ cho giữ assertion vô thời hạn; cần xác nhận ít nhất hai chu kỳ trên thiết bị. Có thể hao pin hơn khi bật.
