import 'package:image_picker/image_picker.dart';

class VideoPickerService {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> pickVideoFromGallery() async {
    return _picker.pickVideo(
      source: ImageSource.gallery,
    );
  }
}
