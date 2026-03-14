import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'inference_provider.dart';

// Provider lưu trạng thái camera đang dùng (trước/sau)
class CameraLensNotifier extends Notifier<CameraLensDirection> {
  @override
  CameraLensDirection build() => CameraLensDirection.front;

  void toggle() {
    state = state == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
  }
}

final cameraLensProvider =
    NotifierProvider<CameraLensNotifier, CameraLensDirection>(
      CameraLensNotifier.new,
    );

final cameraProvider = FutureProvider.autoDispose<CameraController>((
  ref,
) async {
  // 1. Xin quyền Camera
  final status = await Permission.camera.request();
  if (!status.isGranted) {
    throw Exception("Vui lòng cấp quyền Camera để ứng dụng hoạt động!");
  }

  // 2. Lấy hướng camera đang được chọn
  final lensDirection = ref.watch(cameraLensProvider);

  // 3. Lấy danh sách Camera và chọn đúng camera
  final cameras = await availableCameras();
  final selectedCamera = cameras.firstWhere(
    (c) => c.lensDirection == lensDirection,
    orElse: () => cameras.first,
  );

  // 4. Khởi tạo Controller (480p, 30fps)
  final controller = CameraController(
    selectedCamera,
    ResolutionPreset.medium,
    enableAudio: false,
    fps: 30,
    // BẮT BUỘC: Ép định dạng ảnh xuất ra là NV21 (Android) hoặc BGRA (iOS)
    imageFormatGroup: Platform.isIOS
        ? ImageFormatGroup.bgra8888
        : ImageFormatGroup.nv21,
  );

  await controller.initialize();

  // 5. Bơm luồng hình ảnh sang cho InferenceProvider (AI)
  controller.startImageStream((CameraImage image) {
   
    final rotation = selectedCamera.sensorOrientation;

    ref.read(inferenceProvider.notifier).processCameraFrame(image, rotation);
  });

  // 6. Tự động dọn dẹp bộ nhớ khi tắt / chuyển camera
  ref.onDispose(() {
    controller.stopImageStream();
    controller.dispose();
  });

  return controller;
});