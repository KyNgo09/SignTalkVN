import 'package:flutter/services.dart';

class PoseService {
  // Bắt tay với lõi Kotlin thông qua kênh này
  static const MethodChannel _channel = MethodChannel('signtalk.dev/mediapipe');

  Future<List<double>?> extractFeatures(
    Uint8List nv21Bytes,
    int width,
    int height,
    int rotation,
  ) async {
    try {
      // Đẩy mảng byte sang Kotlin tính toán
      final result = await _channel.invokeMethod('extractFeatures', {
        'bytes': nv21Bytes,
        'width': width,
        'height': height,
        'rotation': rotation,
      });

      if (result != null) {
        // Kotlin trả về cục 96 số thập phân chuẩn xác y hệt Python
        return List<double>.from(result);
      }
      return null;
    } catch (e) {
      print("❌ Lỗi Kênh Native: $e");
      return null;
    }
  }

  void dispose() {}
}
