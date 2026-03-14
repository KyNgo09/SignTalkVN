import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../constants/app_constants.dart';

class TFLiteService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;
  String? _loadError;

  bool get isLoaded => _isLoaded;
  String? get loadError => _loadError;

  // ✅ Thêm loadModel để inference_provider gọi được
  Future<bool> loadModel(String modelPath) async {
    await initialize();
    return _isLoaded;
  }

  Future<void> initialize() async {
    try {
      final options = InterpreterOptions()..threads = 2;

      try {
        _interpreter = await Interpreter.fromAsset(
          AppConstants.modelPath,
          options: options,
        );
      } catch (e) {
        log('⚠️ Load with default options failed: $e');
        _interpreter = await Interpreter.fromAsset(AppConstants.modelPath);
      }

      await _loadLabels();
      _isLoaded = true;
      _loadError = null;
      log("✅ TFLite model loaded successfully");
      log("   Input tensors: ${_interpreter!.getInputTensors()}");
      log("   Output tensors: ${_interpreter!.getOutputTensors()}");
    } catch (e) {
      _isLoaded = false;
      _loadError = e.toString();
      debugPrint("❌ Error loading TFLite Model: $e");
      if (e.toString().contains("failed precondition")) {
        debugPrint("👉 LƯU Ý: Lỗi 'failed precondition' thường do model chứa Select TF Ops (ví dụ Flex ops như RNN/LSTM) không được hỗ trợ sẵn trên nền tảng hiện tại (đặc biệt là Windows/Desktop).");
        debugPrint("👉 Cách xử lý: Hãy chạy trên device/emulator Android, VÀ đảm bảo TensorFlow Lite version đang dùng hỗ trợ op này, HOẶC convert lại model TFLite chỉ dùng TFLITE_BUILTINS.");
      }
    }
  }

  Future<void> _loadLabels() async {
    try {
      final jsonString = await rootBundle.loadString(AppConstants.labelsPath);
      final decoded = json.decode(jsonString);

      if (decoded is List) {
        _labels = decoded.map((e) => e.toString()).toList();
      } else if (decoded is Map) {
        _labels = decoded.values.map((e) => e.toString()).toList();
      }
      debugPrint("✅ Đã load thành công ${_labels.length} nhãn!");
    } catch (e) {
      debugPrint("❌ Lỗi đọc file JSON nhãn: $e");
    }
  }

  // ✅ predict trả về Map để inference_provider dùng label + confidence
  Map<String, dynamic> predict(List<List<double>> inputSequence) {
    if (_interpreter == null || _labels.isEmpty) {
      return {'label': 'Đang tải AI...', 'confidence': 0.0};
    }
    if (inputSequence.length != AppConstants.framesPerSequence) {
      return {'label': 'Chờ đủ frame...', 'confidence': 0.0};
    }

    var inputTensor = [inputSequence];
    var outputTensor = List.filled(
      1 * _labels.length,
      0.0,
    ).reshapeTo([1, _labels.length]); // ✅ Đổi tên tránh xung đột

    try {
      _interpreter!.run(inputTensor, outputTensor);

      List<double> probabilities = (outputTensor[0] as List).cast<double>();
      double maxProb = 0.0;
      int maxIndex = -1;

      for (int i = 0; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIndex = i;
        }
      }

      if (maxProb >= AppConstants.confidenceThreshold) {
        return {'label': _labels[maxIndex], 'confidence': maxProb};
      } else {
        return {
          'label': 'Không rõ (${(maxProb * 100).toStringAsFixed(1)}%)',
          'confidence': maxProb,
        };
      }
    } catch (e) {
      debugPrint("Lỗi khi Inference: $e");
      return {'label': 'Lỗi tính toán', 'confidence': 0.0};
    }
  }

  Future<List<dynamic>?> runInference(List<dynamic> input) async {
    if (!_isLoaded || _interpreter == null) {
      log('⚠️ Model chưa được load');
      return null;
    }

    try {
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      // ✅ Bỏ outputType vì không dùng

      final output = List.filled(
        outputShape.reduce((a, b) => a * b),
        0.0,
      ).reshapeTo(outputShape); // ✅ Đổi tên tránh xung đột

      _interpreter!.run(input, output);
      return output;
    } catch (e) {
      log('❌ Inference error: $e');
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}

// ✅ Đổi tên extension thành TFLiteListReshape và method thành reshapeTo
// để tránh xung đột với extension ListShape của tflite_flutter
extension TFLiteListReshape on List {
  List reshapeTo(List<int> shape) {
    if (shape.length == 1) return this;
    int chunkSize = shape.sublist(1).reduce((a, b) => a * b);
    List result = [];
    for (int i = 0; i < length; i += chunkSize) {
      result.add(sublist(i, i + chunkSize).reshapeTo(shape.sublist(1)));
    }
    return result;
  }
}
