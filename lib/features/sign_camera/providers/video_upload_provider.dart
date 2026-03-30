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
      final allFrames = await poseService.processVideoFile(picked.path);

      if (allFrames == null || allFrames.isEmpty) {
        state = state.copyWith(
          status: VideoUploadStatus.error,
          errorMessage: 'Không tìm thấy cử chỉ tay nào trong video này.',
        );
        return;
      }

      // 3. Sliding window
      final int windowSize = AppConstants.framesPerSequence; // 40
      final int stride = 5;
      final List<String> rawPredictions = [];

      // Padding nếu quá ngắn
      if (allFrames.length < windowSize) {
        final last = allFrames.last;
        while (allFrames.length < windowSize) {
          allFrames.add(last);
        }
        final result = tfliteService.predict(allFrames);
        final label = result['label'] as String?;
        final conf = result['confidence'] as double?;
        if (label != null && conf != null && conf > 0.6) {
          rawPredictions.add(label);
        }
      } else {
        for (int i = 0; i <= allFrames.length - windowSize; i += stride) {
          final window = allFrames.sublist(i, i + windowSize);
          final result = tfliteService.predict(window);
          final label = result['label'] as String?;
          final conf = result['confidence'] as double?;
          if (label != null && conf != null && conf > 0.6) {
            rawPredictions.add(label);
          }
        }
      }

      // 4. Lọc nhiễu
      final List<String> finalGlossList = [];
      String? lastWord;
      for (final word in rawPredictions) {
        if (word.isEmpty || word == 'Không rõ') continue;
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

      // Mock câu tiếng Việt (tạm)
      try {
        debugPrint("🤖 Đang nhờ Gemini biên dịch chuỗi: $finalGlossList ...");

        // Đọc Gemini Service từ Provider
        final groqService = ref.read(groqServiceProvider);

        // Gọi API ném chuỗi thô lên Google Server và chờ kết quả
        final finalSentence = await groqService.translateGlossToSentence(
          finalGlossList,
        );

        // THÀNH CÔNG! Cập nhật UI với câu văn hoàn chỉnh
        state = state.copyWith(
          status: VideoUploadStatus.done,
          sentence: finalSentence,
        );

        debugPrint(
          "🎉 Hoàn tất toàn trình Video Upload! Kết quả: $finalSentence",
        );
      } catch (geminiError) {
        debugPrint("❌ Lỗi khi gọi Gemini: $geminiError");

        // Nếu lỡ rớt mạng hoặc Gemini lỗi, ta fallback (chữa cháy) bằng cách in chuỗi thô
        state = state.copyWith(
          status:
              VideoUploadStatus.done, // Vẫn cho Done để UI không bị kẹt Loading
          sentence: finalGlossList.join(" "), // Ghép chay các từ lại với nhau
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
