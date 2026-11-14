# Mở lại Mess — TrollStore / iOS 15

Một chạm vào biểu tượng: yêu cầu iOS đóng Messenger bản App Store (`com.facebook.Messenger`), chờ tiến trình cũ thoát, rồi mở lại. Không có menu hay bước xác nhận trong luồng bình thường. Mỗi lần mở lại tiện ích sẽ chạy một lần; không chạy vòng lặp nền. Đây là cách mở lại app, không sửa lỗi đồng bộ của Meta hoặc làm mới liên tục.

Chỉ dùng trên thiết bị cá nhân có TrollStore. Bản thử nghiệm arm64, deployment target iOS 15.0, cần thử trên iPhone XS Max iOS 15.1. Build thành công không xác nhận quyền riêng hoạt động trên thiết bị thực. Nếu bị từ chối hoặc hết thời gian chờ, app hiện lỗi và không tuyên bố đã khởi động lại thành công.

App chỉ yêu cầu đóng/mở đúng bundle ID cố định; không có API mạng, tài khoản, đọc tin nhắn hay thao tác xóa dữ liệu. Việc đóng Messenger có thể ngắt cuộc gọi hoặc nội dung đang gửi như vuốt tắt app.

Quyền: platform-application, no-sandbox/container-required=false, multitasking.termination và quyền launchapplications của FrontBoard/BackBoard/SpringBoard. Không thêm quyền unsigned-code/JIT bị cấm trên A12+ iOS 15. Các API riêng được tra cứu lúc chạy và kiểm tra selector trước khi gọi. Các quyền rộng thuộc cơ chế TrollStore, không giới hạn được ở riêng Messenger bằng entitlement; giới hạn bundle ID nằm trong mã nguồn.

Tham khảo chữ ký API và entitlement từ [TrollStore](https://github.com/opa334/TrollStore/tree/main/RootHelper) và [runtime header FBSSystemService](https://github.com/JaviSoto/iOS10-Runtime-Headers/blob/master/PrivateFrameworks/FrontBoardServices.framework/FBSSystemService.h). Không tích hợp mã nguồn của TrollStore.

GitHub Actions dùng macOS SDK biên dịch, tạo biểu tượng, ký ad-hoc kèm entitlement và đóng gói IPA. Cài bằng TrollStore; sau đó chạm biểu tượng “Mở lại Mess”.
