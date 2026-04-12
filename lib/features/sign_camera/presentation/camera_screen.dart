import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../providers/camera_provider.dart';
import '../providers/inference_provider.dart';
import '../providers/video_upload_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/presentation/settings_screen.dart';
import '../widgets/landmark_painter.dart';

class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraProvider);
    final inferenceState = ref.watch(inferenceProvider);
    final uploadState = ref.watch(videoUploadProvider); 
    final settingsState = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE5D5B8), Color(0xFFD0C2A5), Color(0xFF9FA092)],
          ),
        ),
        child: SafeArea(
          child: cameraState.when(
            data: (controller) => Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 12),
                    _TopBar(inferenceState: inferenceState),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: _CameraGlass(
                        child: _CameraSurface(
                          controller: controller,
                          uploadState: uploadState,
                          landmarks: settingsState.showSkeleton ? (inferenceState.landmarks ?? const []) : const [],
                          onCloseVideo: () => ref
                              .read(videoUploadProvider.notifier)
                              .clearVideo(),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ResultCard(
                        inferenceState: inferenceState,
                        uploadState: uploadState, // <- thêm
                      ),
                    ),
                    const SizedBox(height: 12),
                    _BottomNav(),
                    const SizedBox(height: 10),
                  ],
                ),
                Positioned(
                  top: 18,
                  right: 18,
                  child: _CircleIcon(
                    icon: Icons.flip_camera_android,
                    onTap: () => ref.read(cameraLensProvider.notifier).toggle(),
                  ),
                ),
              ],
            ),
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            error: (error, _) => Center(
              child: Text(
                error.toString(),
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final InferenceState inferenceState;
  const _TopBar({required this.inferenceState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = inferenceState.status != InferenceStatus.loadFailed;
    final mode = ref.watch(cameraModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _Badge(
            color: active ? const Color(0xFF22D3EE) : Colors.redAccent,
            label: active ? 'AI ACTIVE' : 'AI OFF',
          ),
          const SizedBox(width: 8),
          _Badge(
            color: mode == CameraMode.dictionary ? Colors.amber : Colors.greenAccent,
            label: mode == CameraMode.dictionary ? 'TỪ ĐIỂN' : 'GIAO TIẾP',
          ),
        ],
      ),
    );
  }
}

class _CameraGlass extends StatelessWidget {
  final Widget child;
  const _CameraGlass({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0x22000000), Color(0x33000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white24, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: AspectRatio(aspectRatio: 3 / 4, child: child),
      ),
    );
  }
}

class _CameraSurface extends StatefulWidget {
  final CameraController controller;
  final VideoUploadState uploadState;
  final List<double> landmarks;
  final VoidCallback onCloseVideo;
  const _CameraSurface({
    required this.controller,
    required this.uploadState,
    required this.landmarks,
    required this.onCloseVideo,
  });

  @override
  State<_CameraSurface> createState() => _CameraSurfaceState();
}

class _CameraSurfaceState extends State<_CameraSurface> {
  VideoPlayerController? _videoCtrl;
  PickedVideo? _currentPicked;
  Future<void>? _initVideo;

  @override
  void didUpdateWidget(covariant _CameraSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final picked = widget.uploadState.picked;
    if (picked != null && picked != _currentPicked) {
      _setupVideo(picked);
    } else if (picked == null && _currentPicked != null) {
      _disposeVideo();
    }
  }

  void _setupVideo(PickedVideo picked) {
    _disposeVideo();
    _currentPicked = picked;
    final ctrl = VideoPlayerController.file(File(picked.path));
    _videoCtrl = ctrl;
    _initVideo = ctrl.initialize().then((_) {
      ctrl.setLooping(true);
      ctrl.play();
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  void _disposeVideo() {
    _currentPicked = null;
    _initVideo = null;
    _videoCtrl?.dispose();
    _videoCtrl = null;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showingVideo =
        widget.uploadState.picked != null && _videoCtrl != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!showingVideo)
          Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(widget.controller),
              _AnimatedLandmarkOverlay(landmarks: widget.landmarks),
              _CornersOverlay(),
            ],
          )
        else
          FutureBuilder(
            future: _initVideo,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  _videoCtrl != null) {
                return FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoCtrl!.value.size.width,
                    height: _videoCtrl!.value.size.height,
                    child: VideoPlayer(_videoCtrl!),
                  ),
                );
              }
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
          ),
        if (showingVideo)
          Positioned(
            top: 10,
            right: 10,
            child: InkWell(
              onTap: widget.onCloseVideo,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
      ],
    );
  }
}

class _CornersOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const cornerSize = 28.0;
    const stroke = 3.0;
    const color = Color(0xFF22D3EE);
    return Stack(
      children: [
        _corner(Alignment.topLeft, cornerSize, stroke, color),
        _corner(Alignment.topRight, cornerSize, stroke, color, isLeft: false),
        _corner(Alignment.bottomLeft, cornerSize, stroke, color, isTop: false),
        _corner(
          Alignment.bottomRight,
          cornerSize,
          stroke,
          color,
          isLeft: false,
          isTop: false,
        ),
      ],
    );
  }

  Widget _corner(
    Alignment align,
    double s,
    double w,
    Color c, {
    bool isLeft = true,
    bool isTop = true,
  }) {
    return Align(
      alignment: align,
      child: Padding(
        padding: EdgeInsets.all(10),
        child: CustomPaint(
          size: Size(s, s),
          painter: _CornerPainter(c, w, isLeft: isLeft, isTop: isTop),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double stroke;
  final bool isLeft, isTop;
  _CornerPainter(
    this.color,
    this.stroke, {
    required this.isLeft,
    required this.isTop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    if (isLeft && isTop) {
      path.moveTo(0, size.height * 0.6);
      path.lineTo(0, 0);
      path.lineTo(size.width * 0.6, 0);
    } else if (!isLeft && isTop) {
      path.moveTo(size.width * 0.4, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height * 0.6);
    } else if (isLeft && !isTop) {
      path.moveTo(0, size.height * 0.4);
      path.lineTo(0, size.height);
      path.lineTo(size.width * 0.6, size.height);
    } else {
      path.moveTo(size.width * 0.4, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, size.height * 0.4);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Thêm map mã nhãn -> tiếng Việt (có dấu)
const Map<String, String> _vnLabelMap = {
  'AN': 'Ăn',
  'BAC_SI': 'Bác sĩ',
  'BAN': 'Bạn',
  'BAO_NHIEU': 'Bao nhiêu',
  'BUON': 'Buồn',
  'CAM_ON': 'Cảm ơn',
  'CHA': 'Cha',
  'DAU': 'Đau',
  'DI': 'Đi',
  'GHET': 'Ghét',
  'GI': 'Gì',
  'GIAO_VIEN': 'Giáo viên',
  'HEN_GAP_LAI': 'Hẹn gặp lại',
  'HIEU': 'Hiểu',
  'HOC': 'Học',
  'KHI_NAO': 'Khi nào',
  'KHOE': 'Khỏe',
  'LAM': 'Làm',
  'ME': 'Mẹ',
  'MET': 'Mệt',
  'NGU': 'Ngủ',
  'O_DAU': 'Ở đâu',
  'TAM_BIET': 'Tạm biệt',
  'THICH': 'Thích',
  'TOI': 'Tôi',
  'UONG': 'Uống',
  'VE': 'Về',
  'VUI': 'Vui',
  'XIN_CHAO': 'Xin chào',
  'XIN_LOI': 'Xin lỗi',
  'YEU': 'Yêu',
};

class _ResultCard extends StatelessWidget {
  final InferenceState inferenceState;
  final VideoUploadState uploadState; // <- thêm
  const _ResultCard({required this.inferenceState, required this.uploadState});

  @override
  Widget build(BuildContext context) {
    final bool fromUpload =
        uploadState.status == VideoUploadStatus.done &&
        (uploadState.sentence?.isNotEmpty ?? false);

    late String displayLabel;
    late String titleText;
    String conf = '--';

    if (fromUpload) {
      titleText = 'VIDEO PREDICTION';
      displayLabel = uploadState.sentence!;
      conf = '95%';
    } else if (inferenceState.isRecording) {
      titleText = 'GHI HÌNH';
      displayLabel = 'Đang thu thập động tác...';
    } else if (inferenceState.status == InferenceStatus.processingConversation) {
      titleText = 'ĐANG DỊCH (GROQ)';
      displayLabel = 'Đang ghép câu...';
    } else if (inferenceState.conversationResult != null) {
      titleText = 'LỜI THOẠI (GIAO TIẾP)';
      displayLabel = inferenceState.conversationResult!;
      conf = '90%';
    } else {
      titleText = inferenceState.status == InferenceStatus.result ? 'TỪ ĐIỂN' : 'SCANNING';
      final rLabel = inferenceState.label;
      displayLabel = rLabel != null ? (_vnLabelMap[rLabel] ?? rLabel) : 'Đang quét...';
      if (inferenceState.confidence != null) {
        conf = '${(inferenceState.confidence! * 100).toStringAsFixed(0)}%';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E26).withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF22D3EE), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleText,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  displayLabel.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'CONF.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 11,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Text(
                    conf,
                    style: const TextStyle(
                      color: Color(0xFF22D3EE),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.translate,
                color: Colors.white.withOpacity(0.7),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                fromUpload
                    ? 'Mock prediction from video upload'
                    : 'Vietnamese Sign Language',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1E26).withOpacity(0.9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.video_library_outlined,
                label: 'Tải video',
                isActive: false,
                onTap: () async {
                  await ref.read(videoUploadProvider.notifier).pickAndProcess();
                  if (!context.mounted) return;
                  final picked = ref.read(videoUploadProvider).picked;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        picked == null
                            ? 'Bạn chưa chọn video.'
                            : 'Đã chọn: ${p.basename(picked.path)} '
                                  '(${(picked.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB)',
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final mode = ref.watch(cameraModeProvider);
                  return _NavItem(
                    icon: Icons.photo_camera,
                    label: mode == CameraMode.dictionary ? 'TỪ ĐIỂN' : 'GIAO TIẾP',
                    isActive: true,
                    onTap: () {
                        ref.read(cameraModeProvider.notifier).toggle();
                    },
                  );
                },
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.settings,
                label: 'Cài đặt',
                isActive: false,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF22D3EE) : Colors.white70;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive ? const Color(0x3322D3EE) : Colors.white12,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final Color color;
  final String label;
  const _Badge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════════════
// ✅ Skeleton mượt 60fps — Exponential Smoothing + Ticker
// ═══════════════════════════════════════════════════════════════
// Cách tiếp cận giống AR apps chuyên nghiệp:
// 1. Ticker chạy liên tục ở 60fps
// 2. Mỗi tick: di chuyển vị trí ĐANG HIỂN THỊ về phía TARGET
//    bằng exponential moving average (EMA)
// 3. Chỉ repaint canvas (qua ChangeNotifier), KHÔNG rebuild widget
//
// Ưu điểm so với AnimationController:
// - Không bị bug "nhảy cóc" khi data mới đến giữa animation
// - Tự nhiên hơn — skeleton "đuổi theo" vị trí tay thực tế
// - Hiệu suất cao nhất — chỉ canvas.drawXxx() chạy lại
class _AnimatedLandmarkOverlay extends StatefulWidget {
  final List<double> landmarks;
  const _AnimatedLandmarkOverlay({required this.landmarks});

  @override
  State<_AnimatedLandmarkOverlay> createState() => _AnimatedLandmarkOverlayState();
}

class _AnimatedLandmarkOverlayState extends State<_AnimatedLandmarkOverlay>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late SmoothLandmarkPainter _painter;

  List<double> _displayed = [];
  List<double> _target = [];

  // ── Smoothing ──
  // 0.55 = cân bằng giữa responsive và chống giật
  // (dead zone filter bên dưới sẽ loại bỏ micro-jitter mà smooth không xử lý được)
  static const double _smoothFactor = 0.55;

  // ── Dead zone: bỏ qua di chuyển nhỏ hơn ngưỡng này ──
  // MediaPipe detect cùng 1 vị trí tay nhưng landmark dao động ±0.5-1%
  // → Skeleton rung lắc dù tay đứng yên
  // Ngưỡng 0.008 ≈ 0.8% canvas → bỏ qua noise, giữ chuyển động thật
  static const double _deadZone = 0.008;

  // ── Flicker protection: chờ N frame trước khi xóa skeleton ──
  // MediaPipe đôi khi mất tracking 1-2 frame rồi detect lại
  // → Skeleton nhấp nháy (hiện → mất → hiện)
  // Giữ skeleton thêm 5 frame (~80ms) trước khi xóa
  int _emptyFrameCount = 0;
  static const int _flickerGuardFrames = 5;

  @override
  void initState() {
    super.initState();
    _painter = SmoothLandmarkPainter();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (_target.isEmpty || _target.length != 96) {
      // Flicker protection: chờ vài frame trước khi thực sự xóa skeleton
      if (_displayed.isNotEmpty) {
        _emptyFrameCount++;
        if (_emptyFrameCount > _flickerGuardFrames) {
          _displayed = [];
          _painter.update([]);
        }
      }
      return;
    }

    _emptyFrameCount = 0; // Reset counter khi có data

    // Lần đầu nhận data → snap ngay
    if (_displayed.isEmpty || _displayed.length != 96) {
      _displayed = List<double>.from(_target);
      _painter.update(_displayed);
      return;
    }

    // Exponential smoothing + Dead zone filter
    bool hasChange = false;
    for (int i = 0; i < 96; i++) {
      final diff = _target[i] - _displayed[i];

      // Dead zone: bỏ qua micro-movements (MediaPipe noise)
      if (diff.abs() > _deadZone) {
        _displayed[i] += diff * _smoothFactor;
        hasChange = true;
      }
    }

    if (hasChange) {
      _painter.update(_displayed);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedLandmarkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.landmarks.isNotEmpty) {
      _target = widget.landmarks;
    } else {
      _target = [];
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Widget tree chỉ build 1 LẦN — mọi update qua _painter.notifyListeners()
    return RepaintBoundary(
      child: CustomPaint(painter: _painter),
    );
  }
}
