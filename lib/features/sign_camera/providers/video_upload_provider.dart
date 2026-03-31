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
  // ✅ [Giải pháp 2] Threshold riêng cho video upload, thấp hơn camera realtime
  // Lý do: Khi tải video lên, user đã CHỦ ĐÍCH quay ký hiệu → ít nhiễu hơn camera realtime
  // Camera realtime giữ threshold 0.8 (trong AppConstants) để tránh bắt nhầm cử chỉ tay vô ý
  static const double _videoConfidenceThreshold = 0.4;

  @override
  VideoUploadState build() => const VideoUploadState();

  void clearVideo() {
    state = const VideoUploadState(status: VideoUploadStatus.idle);
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

      // 2. Gọi native bóc tách video
      // ✅ Giờ Kotlin trả về TẤT CẢ frames (kể cả zero-vector khi không detect tay)
      // → Giữ đúng timeline 30fps, sliding window chạy đúng ranh giới ký hiệu
      final allFrames = await poseService.processVideoFile(picked.path);

      if (allFrames == null || allFrames.isEmpty) {
        state = state.copyWith(
          status: VideoUploadStatus.error,
          errorMessage: 'Không tìm thấy cử chỉ tay nào trong video này.',
        );
        return;
      }

      debugPrint("📊 Nhận được ${allFrames.length} frames từ native (bao gồm cả zero-vector)");

      // 3. Sliding window
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
        // ✅ [Giải pháp 2] Dùng threshold riêng cho video upload (0.4 thay vì 0.8)
        if (label != null && conf != null && conf > _videoConfidenceThreshold) {
          rawPredictions.add(label);
        }
      } else {
        for (int i = 0; i <= allFrames.length - windowSize; i += stride) {
          final window = allFrames.sublist(i, i + windowSize);
          final result = tfliteService.predict(window);
          final label = result['label'] as String?;
          final conf = result['confidence'] as double?;
          // ✅ [Giải pháp 2] Dùng threshold riêng cho video upload (0.4 thay vì 0.8)
          if (label != null && conf != null && conf > _videoConfidenceThreshold) {
            rawPredictions.add(label);
          }
        }
      }

      debugPrint("📊 Tổng predictions thô: ${rawPredictions.length}");

      // 4. Lọc nhiễu: loại bỏ từ lặp liên tiếp + từ bắt đầu bằng "Không rõ"
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

      // 5. Dịch chuỗi Gloss thành câu tiếng Việt
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
