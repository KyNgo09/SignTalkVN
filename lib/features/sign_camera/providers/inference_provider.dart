import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/ml/pose_service.dart';
import '../../../core/ml/tflite_service.dart';

import 'video_upload_provider.dart';

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
  final List<double>? landmarks; // NEW

  const InferenceState({
    this.status = InferenceStatus.loading,
    this.label,
    this.confidence,
    this.errorMessage,
    this.currentFrame = 0,
    this.totalFrames = 40,
    this.landmarks,
  });

  InferenceState copyWith({
    InferenceStatus? status,
    String? label,
    double? confidence,
    String? errorMessage,
    int? currentFrame,
    int? totalFrames,
    List<double>? landmarks,
  }) {
    return InferenceState(
      status: status ?? this.status,
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      errorMessage: errorMessage ?? this.errorMessage,
      currentFrame: currentFrame ?? this.currentFrame,
      totalFrames: totalFrames ?? this.totalFrames,
      landmarks: landmarks ?? this.landmarks,
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
        return '🔄 Đang ghi hình động tác... ($currentFrame)';
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
  bool _hasPredictedCurrentGesture = false; // NEW
  int _landmarkSkip = 0;
  static const int _landmarkStride = 2; // chỉ đẩy lên UI mỗi 2 frame

  // --- CÁC THÔNG SỐ CỦA CƠ CHẾ TRIGGER-ON-DROP ---
  int _nullPatienceCount = 0;
  static const int _maxNullAllowed = 2; // Chờ ~0.3s sau khi buông tay
  static const int _minFramesForValidGesture =
      2; // Phải múa ít nhất 8 frame mới tính là 1 từ

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

  Future<void> processCameraFrame(
    CameraImage image,
    int rotation,
    bool isFrontCamera,
  ) async {
    final uploadState = ref.read(videoUploadProvider);
    if (uploadState.picked != null) {
      return; // Khóa AI Camera khi đang phát video đã upload
    }

    if (_isProcessing) return;
    _isProcessing = true;

    try {
      late Uint8List bytes;
      if (image.format.group == ImageFormatGroup.bgra8888) {
        bytes = image.planes[0].bytes;
      } else {
        bytes = _convertYUV420ToNV21(image);
      }

      // GỌI NATIVE: trả về Map {features, landmarks}
      final resultData = await _poseService.extractFeatures(
        bytes,
        image.width,
        image.height,
        rotation,
        isFrontCamera,
      );

      // KỊCH BẢN 1: KHÔNG THẤY TAY
      if (resultData == null) {
        _nullPatienceCount++;

        if (_nullPatienceCount > _maxNullAllowed) {
          if (_frameBuffer.length >= _minFramesForValidGesture) {
            final snapshot = List<List<double>>.from(_frameBuffer);
            final lastFrame = snapshot.last;
            while (snapshot.length < AppConstants.framesPerSequence) {
              snapshot.add(lastFrame);
            }

            final infer = _tfliteService.predict(snapshot);
            final labelStr = infer['label'] as String?;
            final confidenceVal = infer['confidence'] as double?;
            if (labelStr != null &&
                confidenceVal != null &&
                confidenceVal >= 0.7) {
              state = state.copyWith(
                label: labelStr,
                confidence: confidenceVal,
                status: InferenceStatus.result,
                currentFrame: 0,
                landmarks: const [], // xóa khung xương
              );
            }
          } else {
            if (state.status == InferenceStatus.detecting) {
              state = state.copyWith(
                status: InferenceStatus.ready,
                currentFrame: 0,
                landmarks: const [], // xóa khung xương
              );
            }
          }
          _frameBuffer.clear();
          _hasPredictedCurrentGesture = false;
        } else {
          // khi chưa vượt ngưỡng, vẫn xoá khung xương để tránh vẽ sai
          state = state.copyWith(landmarks: const []);
        }
      }
      // KỊCH BẢN 2: ĐANG THẤY TAY
      else {
        _nullPatienceCount = 0;

        // Bóc tách Map ra thành 2 mảng
        final List<double> features = (resultData['features'] as List)
            .cast<double>();
        final List<double> rawLandmarks = (resultData['landmarks'] as List)
            .cast<double>();

        // Đưa features vào bộ nhớ cho AI
        _frameBuffer.add(features);
        if (_frameBuffer.length > AppConstants.framesPerSequence) {
          _frameBuffer.removeAt(0);
        }

        // Đẩy landmarks lên UI (và giữ trigger logic)
        if (!_hasPredictedCurrentGesture &&
            _frameBuffer.length >= AppConstants.framesPerSequence) {
          final snapshot = List<List<double>>.from(_frameBuffer);
          final infer = _tfliteService.predict(snapshot);
          final labelStr = infer['label'] as String?;
          final confidenceVal = infer['confidence'] as double?;
          if (labelStr != null &&
              confidenceVal != null &&
              confidenceVal >= 0.7) {
            state = state.copyWith(
              label: labelStr,
              confidence: confidenceVal,
              status: InferenceStatus.result,
              currentFrame: 0,
              landmarks: rawLandmarks, // vẽ khung xương tay
            );
            _hasPredictedCurrentGesture = true;
          } else {
            state = state.copyWith(
              status: InferenceStatus.detecting,
              currentFrame: _frameBuffer.length,
              landmarks: rawLandmarks,
            );
          }
        } else {
          state = state.copyWith(
            status: InferenceStatus.detecting,
            currentFrame: _frameBuffer.length,
            landmarks: rawLandmarks,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi xử lý frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final nv21 = Uint8List(width * height * 3 ~/ 2);
    int idY = 0;
    int idUV = width * height;

    for (int y = 0; y < height; y++) {
      nv21.setRange(idY, idY + width, yPlane.bytes, y * yRowStride);
      idY += width;
    }

    for (int y = 0; y < height ~/ 2; y++) {
      final uvOffset = y * uvRowStride;
      for (int x = 0; x < width ~/ 2; x++) {
        final index = uvOffset + (x * uvPixelStride);
        nv21[idUV++] = vPlane.bytes[index];
        nv21[idUV++] = uPlane.bytes[index];
      }
    }
    return nv21;
  }
}

final inferenceProvider = NotifierProvider<InferenceNotifier, InferenceState>(
  InferenceNotifier.new,
);
