import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'features/sign_camera/presentation/camera_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const ProviderScope(child: SignTalkApp()));
}

class SignTalkApp extends StatelessWidget {
  const SignTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SignTalkVN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(), // Dùng nền tối cho dễ nhìn Camera
      home: const CameraScreen(), // Trỏ thẳng vào màn hình UI của chúng ta
    );
  }
}
