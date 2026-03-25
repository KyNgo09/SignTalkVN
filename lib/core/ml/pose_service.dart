import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PoseService {
  static const platform = MethodChannel('signtalk.dev/mediapipe');
  // --- HÀM 1: DÙNG CHO CAMERA (Nhận về Map để vẽ khung xương) ---
  Future<Map<String, List<double>>?> extractFeatures(
    Uint8List bytes,
    int width,
    int height,
    int rotation,
    bool isFrontCamera,
  ) async {
    try {
      final result = await platform.invokeMethod('extractFeatures', {
        'bytes': bytes,
        'width': width,
        'height': height,
        'rotation': rotation,
        'isFrontCamera': isFrontCamera,
      });

      if (result != null) {
        // Parse dữ liệu dạng Map từ Kotlin gửi sang
        final map = Map<String, dynamic>.from(result);
        return {
          'features': (map['features'] as List).cast<double>(),
          'landmarks': (map['landmarks'] as List).cast<double>(),
        };
      }
      return null;
    } catch (e) {
      debugPrint("❌ Lỗi PoseService (extractFeatures): $e");
      return null;
    }
  }

  // --- HÀM 2: DÙNG CHO VIDEO UPLOAD (Chỉ nhận mảng AI Features) ---
  Future<List<List<double>>?> processVideoFile(String videoPath) async {
    try {
      final result = await platform.invokeMethod('processVideoFile', {
        'videoPath': videoPath,
      });

      if (result != null) {
        final List<dynamic> outerList = result as List<dynamic>;
        return outerList
            .map((innerList) => (innerList as List<dynamic>).cast<double>())
            .toList();
      }
      return null;
    } catch (e) {
      debugPrint("❌ Lỗi PoseService (processVideoFile): $e");
      return null;
    }
  }

  void dispose() {}
}
