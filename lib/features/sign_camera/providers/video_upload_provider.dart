import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
// import '../../../core/ml/pose_service.dart';
// import '../../../core/ml/tflite_service.dart';
import '../providers/inference_provider.dart';
import '../services/video_picker_service.dart';
import '../../../core/ml/groq_service.dart'; 
class PickedVideo {
  final String path;
  final int sizeBytes;
  const PickedVideo({required this.path, required this.sizeBytes});
}

enum VideoUploadStatus { idle, picking, processing, done, error }

class VideoUploadState {
  final VideoUploadStatus status;
  final PickedVideo? picked;
  final List<String> gloss;
  final String? sentence;
  final String? errorMessage;

  const VideoUploadState({
    this.status = VideoUploadStatus.idle,
    this.picked,
    this.gloss = const [],
    this.sentence,
    this.errorMessage,
  });

  VideoUploadState copyWith({
    VideoUploadStatus? status,
    PickedVideo? picked,
    List<String>? gloss,
    String? sentence,
    String? errorMessage,
  }) {
    return VideoUploadState(
      status: status ?? this.status,
      picked: picked ?? this.picked,
      gloss: gloss ?? this.gloss,
      sentence: sentence ?? this.sentence,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

final videoPickerServiceProvider = Provider<VideoPickerService>(
  (ref) => VideoPickerService(),
);

// Provider auto-dispose
final videoUploadProvider =
    NotifierProvider.autoDispose<VideoUploadNotifier, VideoUploadState>(
      VideoUploadNotifier.new,
    );

class VideoUploadNotifier extends Notifier<VideoUploadState> {
  // Threshold riêng cho video upload, thấp hơn camera realtime
  // Camera realtime giữ threshold 0.8 (trong AppConstants) để tránh bắt nhầm cử chỉ vô ý
  static const double _videoConfidenceThreshold = 0.4;

  @override
  VideoUploadState build() => const VideoUploadState();

  void clearVideo() {
    state = const VideoUploadState(status: VideoUploadStatus.idle);
  }

  // =========================================================================
  // NỘI SUY 10fps lên 30fps để khớp model BiLSTM (train ở 30fps)
  // =========================================================================
  // Giữa 2 frame thực (cách nhau 100ms), tạo thêm 2 frame trung gian
  // bằng linear interpolation trên 96 features.
  //
  // Ví dụ: Frame A (t=0ms) và Frame B (t=100ms)
  //   → Frame t=33ms:  features = A + (B - A) × 0.33
  //   → Frame t=66ms:  features = A + (B - A) × 0.67
  //   → Frame t=100ms: features = B (frame thực)
  //
  // Tại sao hoạt động: ký hiệu tay di chuyển liên tục (không teleport),
  // nên linear interpolation giữa 2 vị trí cách nhau 100ms là chính xác.
  // Model BiLSTM nhìn cả chuỗi 40 frame nên dung sai nhỏ không ảnh hưởng.
  List<List<double>> _interpolateTo30fps(List<List<double>> frames10fps) {
    if (frames10fps.length <= 1) return frames10fps;

    final List<List<double>> result = [];
    final int featureCount = frames10fps[0].length; // 96

    for (int i = 0; i < frames10fps.length - 1; i++) {
      final frameA = frames10fps[i];
      final frameB = frames10fps[i + 1];

      // Thêm frame gốc A
      result.add(frameA);

      // Tạo 2 frame nội suy giữa A và B (tại t=0.33 và t=0.67)
      for (final ratio in [1.0 / 3.0, 2.0 / 3.0]) {
        final interpolated = List<double>.generate(featureCount, (k) {
          return frameA[k] + (frameB[k] - frameA[k]) * ratio;
        });
        result.add(interpolated);
      }
    }

    // Thêm frame cuối cùng
    result.add(frames10fps.last);

    return result;
  }

  Future<void> pickAndProcess() async {
    // 1. Chọn video
    state = state.copyWith(
      status: VideoUploadStatus.picking,
      errorMessage: null,
    );

    final picker = ref.read(videoPickerServiceProvider);
    final file = await picker.pickVideoFromGallery();
    if (file == null) {
      state = state.copyWith(status: VideoUploadStatus.idle);
      return;
    }

    final f = File(file.path);
    final size = await f.length();
    final picked = PickedVideo(path: file.path, sizeBytes: size);

    // Hiển thị UI processing
    state = state.copyWith(
      status: VideoUploadStatus.processing,
      picked: picked,
      gloss: const [],
      sentence: null,
      errorMessage: null,
    );

    try {
      // Đọc service
      final poseService = ref.read(poseServiceProvider);
      final tfliteService = ref.read(tfliteServiceProvider);

      // Đảm bảo model đã load
      if (!tfliteService.isLoaded) {
        await tfliteService.initialize();
      }

      // 2. Gọi native bóc tách video (10fps)
      final frames10fps = await poseService.processVideoFile(picked.path);

      if (frames10fps == null || frames10fps.isEmpty) {
        state = state.copyWith(
          status: VideoUploadStatus.error,
          errorMessage: 'Không tìm thấy cử chỉ tay nào trong video này.',
        );
        return;
      }

      debugPrint("📊 Nhận ${frames10fps.length} frames @10fps từ native");

      // 3. ✅ NỘI SUY lên 30fps để khớp model BiLSTM
      // 10fps → 30fps: mỗi khoảng 100ms tạo thêm 2 frame trung gian
      final allFrames = _interpolateTo30fps(frames10fps);
      debugPrint("📊 Sau nội suy: ${allFrames.length} frames @30fps");

      // 4. Sliding window
      final int windowSize = AppConstants.framesPerSequence; // 40 frames = 1.33 giây ở 30fps
      final int stride = 5; // Trượt 5 frame mỗi bước = ~0.17 giây
      final List<String> rawPredictions = [];

      // Padding nếu video quá ngắn (< 40 frames = < 1.33 giây)
      if (allFrames.length < windowSize) {
        final last = allFrames.last;
        while (allFrames.length < windowSize) {
          allFrames.add(last);
        }
        final result = tfliteService.predict(allFrames);
        final label = result['label'] as String?;
        final conf = result['confidence'] as double?;
        if (label != null && conf != null && conf > _videoConfidenceThreshold) {
          rawPredictions.add(label);
        }
      } else {
        for (int i = 0; i <= allFrames.length - windowSize; i += stride) {
          final window = allFrames.sublist(i, i + windowSize);
          final result = tfliteService.predict(window);
          final label = result['label'] as String?;
          final conf = result['confidence'] as double?;
          if (label != null && conf != null && conf > _videoConfidenceThreshold) {
            rawPredictions.add(label);
          }
        }
      }

      debugPrint("📊 Tổng predictions thô: ${rawPredictions.length}");

      // 5. Lọc nhiễu: loại bỏ từ lặp liên tiếp + từ bắt đầu bằng "Không rõ"
      final List<String> finalGlossList = [];
      String? lastWord;
      for (final word in rawPredictions) {
        if (word.isEmpty || word.startsWith('Không rõ')) continue;
        if (word != lastWord) {
          finalGlossList.add(word);
          lastWord = word;
        }
      }
      debugPrint("🔍 Chuỗi Gloss sau khi lọc: $finalGlossList");
      state = state.copyWith(gloss: finalGlossList);

      if (finalGlossList.isEmpty) {
        state = state.copyWith(
          status: VideoUploadStatus.done,
          sentence: 'Không thể nhận diện rõ các ký hiệu.',
        );
        return;
      }

      // 6. Dịch chuỗi Gloss thành câu tiếng Việt
      try {
        debugPrint("🤖 Đang nhờ dịch chuỗi: $finalGlossList ...");

        final groqService = ref.read(groqServiceProvider);
        final finalSentence = await groqService.translateGlossToSentence(
          finalGlossList,
        );

        state = state.copyWith(
          status: VideoUploadStatus.done,
          sentence: finalSentence,
        );

        debugPrint(
          "🎉 Hoàn tất toàn trình Video Upload! Kết quả: $finalSentence",
        );
      } catch (geminiError) {
        debugPrint("❌ Lỗi khi dịch: $geminiError");

        // Fallback: ghép chuỗi Gloss thô
        state = state.copyWith(
          status: VideoUploadStatus.done,
          sentence: finalGlossList.join(" "),
        );
      }
    } catch (e) {
      debugPrint("❌ Lỗi toàn trình Video Upload: $e");
      state = state.copyWith(
        status: VideoUploadStatus.error,
        errorMessage: 'Đã xảy ra lỗi hệ thống khi xử lý video.',
      );
    }
  }
}
