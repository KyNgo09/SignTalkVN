import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/video_picker_service.dart';

class PickedVideo {
  final String path;
  final int sizeBytes;
  const PickedVideo({required this.path, required this.sizeBytes});
}

final videoPickerServiceProvider = Provider<VideoPickerService>(
  (ref) => VideoPickerService(),
);

// Auto-dispose Notifier
final videoUploadProvider =
    NotifierProvider.autoDispose<VideoUploadNotifier, PickedVideo?>(
      VideoUploadNotifier.new,
    );

class VideoUploadNotifier extends Notifier<PickedVideo?> {
  @override
  PickedVideo? build() => null;

  Future<PickedVideo?> pickFromGallery() async {
    final picker = ref.read(videoPickerServiceProvider);
    final file = await picker.pickVideoFromGallery();
    if (file == null) return null;

    final f = File(file.path);
    final size = await f.length();

    final picked = PickedVideo(path: file.path, sizeBytes: size);
    state = picked;
    return picked;
  }
}
