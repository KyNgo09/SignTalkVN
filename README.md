# SignTalkVN – Ứng dụng Phiên dịch Ngôn ngữ Ký hiệu Việt Nam bằng AI

**SignTalkVN** là ứng dụng di động phát triển trên nền tảng **Flutter**, sử dụng **AI** để phiên dịch Ngôn ngữ Ký hiệu Việt Nam (VSL) sang văn bản tiếng Việt theo thời gian thực (camera trực tiếp) hoặc gián tiếp (video upload).

Ứng dụng được thiết kế tối ưu để hoạt động ổn định trên nhiều loại thiết bị, đảm bảo độ chính xác cao ngay cả trong điều kiện phần cứng khác nhau.

---

## Kiến trúc & Công nghệ

- **Frontend:** Flutter, quản lý trạng thái bằng Riverpod  
- **Native Android:** Kotlin, truy cập trực tiếp API Camera và tích hợp Google ML Kit / MediaPipe để trích xuất khung xương thời gian thực  
- **AI Core:** Mạng BiLSTM nhẹ, triển khai qua TFLite (`tflite_flutter`)  
- **Dịch thuật:** Kết nối API Groq, sử dụng Prompt Engineering và từ điển nhãn (`_vnLabelMap`) để chuyển đổi dữ liệu thành ngôn ngữ tự nhiên  

---

## Các chế độ hoạt động

### 1. Video Upload
- Giảm độ phân giải khung hình xuống tối đa 320px để tiết kiệm RAM  
- Lấy mẫu khung hình theo bước thời gian (100ms), chuẩn hóa về 10fps  
- Dart nội suy lại thành 30fps để phù hợp với mô hình AI  

### 2. Dictionary Mode
- Camera cố định ở độ phân giải trung bình (~480p, 30fps)  
- Bộ đệm khung hình (40 frames) được phân tích, nếu AI nhận diện >70% thì tạm dừng cho đến khi người dùng hạ tay  
- Phù hợp cho luyện tập với từ đơn, ký hiệu riêng lẻ  

### 3. Conversation Mode
- BiLSTM hoạt động theo cửa sổ trượt, thích ứng với dao động fps  
- Dữ liệu tọa độ được chuẩn hóa theo tỷ lệ vai-ngực, đảm bảo ổn định dù khoảng cách camera thay đổi  
- Hệ thống tự nhận biết điểm kết thúc câu dựa trên vị trí tay, sau đó gửi dữ liệu lên Groq API để dịch  

---

## Hướng dẫn cài đặt

1. Cài đặt Flutter SDK phù hợp  
2. Chạy `flutter pub get` để tải thư viện  
3. Thêm file `.env` chứa API Key của Groq vào thư mục gốc  
4. Khởi chạy bằng `flutter run --debug` để theo dõi log và kiểm thử  

---

## License
Dự án được phát triển cho mục đích nghiên cứu và ứng dụng thực tế. Vui lòng tham khảo giấy phép đi kèm trước khi sử dụng hoặc phân phối.
