# XemPhim iOS 1.1.2 — native fullscreen

IPA phát hành từ commit d18755834ece66512f38d8c3ffc502bcead05278, GitHub run https://github.com/tranchautien1995-hub/phimbar-ios/actions/runs/44890465152 . Artifact 14701932197. SHA256 d6b9b55b8c311427fb33b2fa56988cf8bbe9d13534e929ae4afa5e59f6cd233e, kích thước 610892 bytes. Cùng bundle ID vn.onnstream.phimbar.ios, version 1.1.2 build 6, arm64/iOS 15.0.

18 protocol và 8 rental checks đạt. UI test bấm trực tiếp đã xác nhận chạm video hiện điều khiển, phát, tạm dừng và Close quay về màn phát có tiêu đề Phim kiểm tra. Đã xem ảnh native-paused và returned-to-app-player: có nút play, lùi/tiến, thanh thời gian và phụ đề; màn app giữ cùng mốc 00:43 sau Close.

Log UI cũ có bước chọn nhầm Volume Slider, không phải timeline. Không tính bước đó là phép thử kéo thanh thời gian; test đã được đổi tên và bỏ bước không liên quan. Seek bằng AVPlayer được kiểm tra riêng ở run https://github.com/tranchautien1995-hub/phimbar-ios/actions/runs/44885716959 : samePlayer=true, pauseWorked=true, seekWorked=true, positionAfterSeek=75, returnedToPlayer=true, positionAfterReturn=97.468425533. Run này cũng xác nhận video/phụ đề API và web mẫu, Keychain save/read/delete. Lớp phụ đề sau đó được bổ sung isUserInteractionEnabled=false và kiểm tra chạm lại bằng run cuối.

Chưa thử kéo timeline bằng UITest hoặc chạy trên XS Max iOS 15.1 thật. Chưa thử giao dịch thật. Không thực hiện cài đặt app nào trên box Onn; phần Android đang được để lại theo yêu cầu người dùng.
