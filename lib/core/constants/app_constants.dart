class AppConstants {
  // Cấu hình Model
  static const String modelPath = 'assets/models/signtalk_model.tflite';
  static const String labelsPath = 'assets/models/labels_map.json';

  // Cấu hình Tensor Đầu vào
  static const int framesPerSequence = 40; // Số frame cần gom
  static const int featuresPerFrame = 96; // 32 điểm x 3 tọa độ (x,y,z)

  // Ngưỡng tự tin (Confidence Threshold)
  static const double confidenceThreshold =
      0.7; // Chỉ nhận chữ nếu AI chắc chắn > 70%
}
