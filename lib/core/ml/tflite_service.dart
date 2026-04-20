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
    } catch (e) {
      _isLoaded = false;
      _loadError = e.toString();
      debugPrint("❌ Error loading TFLite Model: $e");
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

  Map<String, dynamic> predict(List<List<double>> inputSequence) {
    if (_interpreter == null || _labels.isEmpty) {
      return {'label': 'Đang tải AI...', 'confidence': 0.0};
    }

    // Kiểm tra an toàn độ dài sequence
    if (inputSequence.length != AppConstants.framesPerSequence) {
      return {'label': 'Chờ đủ frame...', 'confidence': 0.0};
    }

    try {
      // 1. TẠO TENSOR ĐẦU VÀO CHUẨN (Ép kiểu nghiêm ngặt để TFLite C++ đọc được)
      var inputTensor = List.generate(
        1,
        (i) => List.generate(
          AppConstants.framesPerSequence, // 40
          (j) => List.generate(
            AppConstants.featuresPerFrame, // 96
            (k) => inputSequence[j][k],
          ),
        ),
      );

      // 2. TẠO TENSOR ĐẦU RA CHUẨN
      var outputTensor = List.generate(
        1,
        (i) => List.filled(_labels.length, 0.0),
      );

      // 3. CHẠY SUY LUẬN
      // Cấp phát lại tensor & reset state của BiLSTM (tránh tàn dư state từ phép tính sliding window trước đó)
      _interpreter!.allocateTensors();
      _interpreter!.run(inputTensor, outputTensor);

      // 4. TRÍCH XUẤT KẾT QUẢ
      List<double> probabilities = outputTensor[0];
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

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}

