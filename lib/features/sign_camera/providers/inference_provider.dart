import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/ml/pose_service.dart';
import '../../../core/ml/tflite_service.dart';
import '../../../core/ml/groq_service.dart';

import 'video_upload_provider.dart';

final tfliteServiceProvider = Provider<TFLiteService>((ref) => TFLiteService());
final poseServiceProvider = Provider<PoseService>((ref) => PoseService());

enum InferenceStatus { loading, loadFailed, ready, detecting, result, processingConversation }
enum CameraMode { dictionary, conversation }

class CameraModeNotifier extends Notifier<CameraMode> {
  @override
  CameraMode build() => CameraMode.dictionary;
  void toggle() {
    state = state == CameraMode.dictionary ? CameraMode.conversation : CameraMode.dictionary;
  }
}

final cameraModeProvider = NotifierProvider<CameraModeNotifier, CameraMode>(CameraModeNotifier.new);

class InferenceState {
  final InferenceStatus status;
  final String? label;
  final double? confidence;
  final String? errorMessage;
  final int currentFrame;
  final int totalFrames;
  final List<double>? landmarks;
  final bool isRecording;
  final String? conversationResult;

  const InferenceState({
    this.status = InferenceStatus.loading,
    this.label,
    this.confidence,
    this.errorMessage,
    this.currentFrame = 0,
    this.totalFrames = 40,
    this.landmarks,
    this.isRecording = false,
    this.conversationResult,
  });

  InferenceState clearText() {
    return InferenceState(
      status: status,
      errorMessage: errorMessage,
      currentFrame: currentFrame,
      totalFrames: totalFrames,
      landmarks: landmarks,
      isRecording: isRecording,
    );
  }

  InferenceState copyWith({
    InferenceStatus? status,
    String? label,
    double? confidence,
    String? errorMessage,
    int? currentFrame,
    int? totalFrames,
    List<double>? landmarks,
    bool? isRecording,
    String? conversationResult,
  }) {
    return InferenceState(
      status: status ?? this.status,
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      errorMessage: errorMessage ?? this.errorMessage,
      currentFrame: currentFrame ?? this.currentFrame,
      totalFrames: totalFrames ?? this.totalFrames,
      landmarks: landmarks ?? this.landmarks,
      isRecording: isRecording ?? this.isRecording,
      conversationResult: conversationResult ?? this.conversationResult,
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
      case InferenceStatus.processingConversation:
        return '🤖 Đang dịch lời thoại...';
      case InferenceStatus.result:
        final conf = confidence != null
            ? ' (${(confidence! * 100).toStringAsFixed(1)}%)'
            : '';
        return conversationResult != null 
             ? '💬 ${conversationResult}' 
             : '🤟 ${label ?? 'Không rõ'}$conf';
    }
  }
}

class InferenceNotifier extends Notifier<InferenceState> {
  late TFLiteService _tfliteService;
  late PoseService _poseService;

  final List<List<double>> _frameBuffer = [];
  final List<List<double>> _conversationBuffer = []; // NEW
  bool _isProcessing = false;
  bool _hasPredictedCurrentGesture = false; 
  int _landmarkSkip = 0;
  static const int _landmarkStride = 2; 

  int _nullPatienceCount = 0;
  int _convNullCount = 0; 
  static const int _maxNullAllowed = 2; 
  static const int _maxConvNullAllowed = 75; // Chờ 2.5 giây để ngắt câu (thay vì 1s)
  static const int _minFramesForValidGesture = 2;

  @override
  InferenceState build() {
    _tfliteService = ref.read(tfliteServiceProvider);
    _poseService = ref.read(poseServiceProvider);

    ref.listen(cameraModeProvider, (previous, next) {
      if (previous != next) {
        Future.microtask(() => _resetModeState());
      }
    });

    Future.microtask(_init);
    return const InferenceState();
  }

  void _resetModeState() {
    _conversationBuffer.clear();
    _frameBuffer.clear();
    _hasPredictedCurrentGesture = false;
    _nullPatienceCount = 0;
    _convNullCount = 0;
    state = state.clearText().copyWith(
      status: InferenceStatus.ready,
      isRecording: false,
      currentFrame: 0,
      landmarks: const [],
    );
  }

  Future<void> _init() async {
    await _tfliteService.initialize();
    state = state.copyWith(status: InferenceStatus.ready);
    debugPrint('✅ Model sẵn sàng');
  }

  void _startAutoRecording() {
    _conversationBuffer.clear();
    state = state.clearText().copyWith(isRecording: true);
  }

  Future<void> _processConversationBuffer() async {
    state = state.copyWith(isRecording: false, status: InferenceStatus.processingConversation);
    
    // Nếu quá ngắn (dưới 10 frames túc vài mili-giây) thì bỏ qua
    if (_conversationBuffer.length < 10) {
      state = state.copyWith(status: InferenceStatus.ready, conversationResult: "Dữ liệu quá ngắn.");
      return;
    }

    final int windowSize = AppConstants.framesPerSequence;
    final int stride = 5;
    
    // Padding data nếu user múa tự nhiên bị thiếu frame (< 40 frames)
    if (_conversationBuffer.length < windowSize) {
      final last = _conversationBuffer.last;
      while (_conversationBuffer.length < windowSize) {
        _conversationBuffer.add(last);
      }
    }

    final List<String> rawPredictions = [];

    for (int i = 0; i <= _conversationBuffer.length - windowSize; i += stride) {
      final window = _conversationBuffer.sublist(i, i + windowSize);
      final infer = _tfliteService.predict(window);
      final labelStr = infer['label'] as String?;
      final conf = infer['confidence'] as double?;
      if (labelStr != null && conf != null && conf >= 0.7) {
        rawPredictions.add(labelStr);
      }
    }

    final List<String> finalGlossList = [];
    String? lastWord;
    for (final word in rawPredictions) {
      if (word.isEmpty || word.startsWith('Không rõ')) continue;
      if (word != lastWord) {
        finalGlossList.add(word);
        lastWord = word;
      }
    }

    if (finalGlossList.isEmpty) {
      state = state.copyWith(status: InferenceStatus.ready, conversationResult: "Không nhận diện được từ nào.");
      return;
    }

    try {
      final groqService = ref.read(groqServiceProvider);
      final finalSentence = await groqService.translateGlossToSentence(finalGlossList);
      state = state.copyWith(status: InferenceStatus.result, conversationResult: finalSentence);
    } catch (e) {
      state = state.copyWith(status: InferenceStatus.result, conversationResult: finalGlossList.join(" "));
    }
  }

  Future<void> processCameraFrame(
    CameraImage image,
    int rotation,
    bool isFrontCamera,
  ) async {
    final uploadState = ref.read(videoUploadProvider);
    if (uploadState.picked != null) return;

    if (_isProcessing) return;
    _isProcessing = true;

    try {
      late Uint8List bytes;
      if (image.format.group == ImageFormatGroup.bgra8888) {
        bytes = image.planes[0].bytes;
      } else {
        bytes = _convertYUV420ToNV21(image);
      }

      final resultData = await _poseService.extractFeatures(
        bytes,
        image.width,
        image.height,
        rotation,
        isFrontCamera,
      );

      final mode = ref.read(cameraModeProvider);

      if (mode == CameraMode.conversation) {
        if (resultData == null) {
          _convNullCount++;
          if (_convNullCount > _maxConvNullAllowed) {
            if (state.isRecording) {
              // KHÔNG dùng await để tránh nghẽn camera khi gọi server Groq
              _processConversationBuffer();
            } else if (state.status != InferenceStatus.processingConversation && state.status != InferenceStatus.result) {
              state = state.copyWith(status: InferenceStatus.ready, landmarks: const []);
            }
          } else {
            if (state.isRecording) {
              if (_conversationBuffer.isNotEmpty) {
                 _conversationBuffer.add(_conversationBuffer.last);
              }
              state = state.copyWith(landmarks: const []);
            }
          }
        } else {
          _convNullCount = 0;
          final List<double> features = (resultData['features'] as List).cast<double>();
          final List<double> rawLandmarks = (resultData['landmarks'] as List).cast<double>();
          
          if (!state.isRecording && state.status != InferenceStatus.processingConversation) {
            _startAutoRecording();
          }
          if (state.isRecording) {
            _conversationBuffer.add(features);
            state = state.copyWith(
              status: InferenceStatus.detecting,
              currentFrame: _conversationBuffer.length,
              landmarks: rawLandmarks,
            );
          }
        }
        return;
      }

      // KỊCH BẢN 1: KHÔNG THẤY TAY (Dictionary Mode)
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
            if (labelStr != null && confidenceVal != null && confidenceVal >= 0.7) {
              state = state.clearText().copyWith(
                label: labelStr,
                confidence: confidenceVal,
                status: InferenceStatus.result,
                currentFrame: 0,
                landmarks: const [],
              );
            } else if (state.status == InferenceStatus.detecting) {
               state = state.copyWith(status: InferenceStatus.ready, currentFrame: 0, landmarks: const []);
            }
          } else {
            if (state.status == InferenceStatus.detecting) {
              state = state.copyWith(status: InferenceStatus.ready, currentFrame: 0, landmarks: const []);
            }
          }
          _frameBuffer.clear();
          _hasPredictedCurrentGesture = false;
        } else {
          state = state.copyWith(landmarks: const []);
        }
      } 
      // KỊCH BẢN 2: ĐANG THẤY TAY (Dictionary Mode)
      else {
        _nullPatienceCount = 0;
        final List<double> features = (resultData['features'] as List).cast<double>();
        final List<double> rawLandmarks = (resultData['landmarks'] as List).cast<double>();

        _frameBuffer.add(features);
        if (_frameBuffer.length > AppConstants.framesPerSequence) {
          _frameBuffer.removeAt(0);
        }

        if (!_hasPredictedCurrentGesture && _frameBuffer.length >= AppConstants.framesPerSequence) {
          final snapshot = List<List<double>>.from(_frameBuffer);
          final infer = _tfliteService.predict(snapshot);
          final labelStr = infer['label'] as String?;
          final confidenceVal = infer['confidence'] as double?;
          if (labelStr != null && confidenceVal != null && confidenceVal >= 0.7) {
            state = state.clearText().copyWith(
              label: labelStr,
              confidence: confidenceVal,
              status: InferenceStatus.result,
              currentFrame: 0,
              landmarks: rawLandmarks, 
            );
            _hasPredictedCurrentGesture = true;
          } else {
            state = state.copyWith(status: InferenceStatus.detecting, currentFrame: _frameBuffer.length, landmarks: rawLandmarks);
          }
        } else {
          state = state.copyWith(status: InferenceStatus.detecting, currentFrame: _frameBuffer.length, landmarks: rawLandmarks);
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
