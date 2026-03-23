import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ĐÃ XÓA IMPORT GOOGLE ML KIT BỊ MÙ NGÓN TAY

import '../../../core/constants/app_constants.dart';
import '../../../core/ml/pose_service.dart';
import '../../../core/ml/tflite_service.dart';

final tfliteServiceProvider = Provider<TFLiteService>((ref) => TFLiteService());
final poseServiceProvider = Provider<PoseService>((ref) => PoseService());

enum InferenceStatus { loading, loadFailed, ready, detecting, result }

class InferenceState {
  final InferenceStatus status;
  final String? label;
  final double? confidence;
  final String? errorMessage;
  final int currentFrame;
  final int totalFrames;

  const InferenceState({
    this.status = InferenceStatus.loading,
    this.label,
    this.confidence,
    this.errorMessage,
    this.currentFrame = 0,
    this.totalFrames = 40,
  });

  InferenceState copyWith({
    InferenceStatus? status,
    String? label,
    double? confidence,
    String? errorMessage,
    int? currentFrame,
    int? totalFrames,
  }) {
    return InferenceState(
      status: status ?? this.status,
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      errorMessage: errorMessage ?? this.errorMessage,
      currentFrame: currentFrame ?? this.currentFrame,
      totalFrames: totalFrames ?? this.totalFrames,
    );
  }

  String get statusMessage {
    switch (status) {
      case InferenceStatus.loading:
        return '⏳ Đang khởi động AI...';
      case InferenceStatus.loadFailed:
        return '❌ Lỗi tải model: ${errorMessage ?? 'Không xác định'}';
      case InferenceStatus.ready:
        return '✅ Đứng vào khung hình nhé!';
      case InferenceStatus.detecting:
        return '🔄 Đang quét động tác: $currentFrame/$totalFrames';
      case InferenceStatus.result:
        final conf = confidence != null
            ? ' (${(confidence! * 100).toStringAsFixed(1)}%)'
            : '';
        return '🤟 ${label ?? 'Không rõ'}$conf';
    }
  }
}

class InferenceNotifier extends Notifier<InferenceState> {
  late TFLiteService _tfliteService;
  late PoseService _poseService;

  final List<List<double>> _frameBuffer = [];
  bool _isProcessing = false;

  int _skipCount = 0;

  static const int _minFramesForPredict = 1;

  @override
  InferenceState build() {
    _tfliteService = ref.read(tfliteServiceProvider);
    _poseService = ref.read(poseServiceProvider);

    Future.microtask(_init);
    return const InferenceState();
  }

  Future<void> _init() async {
    await _tfliteService.initialize();
    state = state.copyWith(status: InferenceStatus.ready);
    debugPrint('✅ Model sẵn sàng');
  }

  // 🔴 LƯU Ý: Chuyển InputImageRotation thành kiểu int rotation
  Future<void> processCameraFrame(CameraImage image, int rotation) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 1. GOM MẢNG BYTE TỪ CAMERA (Định dạng NV21)
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      // 2. GỌI KÊNH NATIVE KOTLIN CHẠY MEDIAPIPE
      final features = await _poseService.extractFeatures(
        bytes,
        image.width,
        image.height,
        rotation,
      );

      if (features == null) {
        _frameBuffer.clear();
        state = state.copyWith(
          status: InferenceStatus.ready,
          label: '👻 Không thấy bàn tay nào',
          currentFrame: 0,
        );
      } else {
        _frameBuffer.add(features);

        if (_frameBuffer.length > AppConstants.framesPerSequence) {
          _frameBuffer.removeAt(0);
        }

        // 3. Nếu mới có dưới _minFramesForPredict frame
        if (_frameBuffer.length < _minFramesForPredict) {
          state = state.copyWith(
            status: InferenceStatus.detecting,
            currentFrame: _frameBuffer.length,
          );
        }
        // 4. ĐÃ ĐỦ FRAME TỐI THIỂU -> BẮT ĐẦU SUY LUẬN NHANH HƠN
        else {
          _skipCount++;

          // Chạy AI mỗi 2 frame (trước là 3) để phản hồi nhanh hơn
          if (_skipCount % 2 != 0) {
            if (state.status != InferenceStatus.result) {
              state = state.copyWith(currentFrame: _frameBuffer.length);
            }
            _isProcessing = false;
            return;
          }

          final snapshot = List<List<double>>.from(
            _frameBuffer.map((f) => List<double>.from(f)),
          );

          // Bổ sung frame cuối cho đủ bộ 10 frame
          final lastFrame = snapshot.last;
          while (snapshot.length < AppConstants.framesPerSequence) {
            snapshot.add(lastFrame);
          }

          final resultData = _tfliteService.predict(snapshot);

          final labelStr = resultData['label'] as String?;
          final confidenceVal = resultData['confidence'] as double?;

          debugPrint(
            "⚡ AI đang nghĩ: [$labelStr] - Tự tin: ${(confidenceVal ?? 0) * 100}% (Đang có ${_frameBuffer.length} frames)",
          );

          if (labelStr != null) {
            state = state.copyWith(
              label: labelStr, // Hiện thẳng lên màn hình dù là "Không rõ"
              confidence: confidenceVal,
              status: InferenceStatus.result,
              currentFrame: _frameBuffer.length,
            );
          } else {
            state = state.copyWith(
              status: InferenceStatus.detecting,
              currentFrame: 40,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi xử lý frame: $e');
    } finally {
      _isProcessing = false;
    }
  }
}

final inferenceProvider = NotifierProvider<InferenceNotifier, InferenceState>(
  InferenceNotifier.new,
);
