import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/camera_provider.dart';
import '../providers/inference_provider.dart';

class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraProvider);
    final inferenceState = ref.watch(inferenceProvider);

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
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(controller),
                            _CornersOverlay(),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ResultCard(inferenceState: inferenceState),
                    ),
                    const SizedBox(height: 12),
                    const _BottomNav(),
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

class _TopBar extends StatelessWidget {
  final InferenceState inferenceState;
  const _TopBar({required this.inferenceState});

  @override
  Widget build(BuildContext context) {
    final active = inferenceState.status != InferenceStatus.loadFailed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _Badge(
            color: active ? const Color(0xFF22D3EE) : Colors.redAccent,
            label: active ? 'AI ACTIVE' : 'AI OFF',
          ),
          const SizedBox(width: 12),
          Text(
            'FPS: 30  |  LAT: ~12ms',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
              letterSpacing: 0.4,
            ),
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

class _ResultCard extends StatelessWidget {
  final InferenceState inferenceState;
  const _ResultCard({required this.inferenceState});

  @override
  Widget build(BuildContext context) {
    final label = inferenceState.label ?? 'Đang quét...';
    final conf = inferenceState.confidence != null
        ? '${(inferenceState.confidence! * 100).toStringAsFixed(0)}%'
        : '--';
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
            inferenceState.status == InferenceStatus.result
                ? 'DETECTED'
                : 'SCANNING',
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
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
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
                'Vietnamese Sign Language',
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

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
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
          children: const [
            Expanded(
              child: _NavItem(
                icon: Icons.video_library_outlined,
                label: 'Tải video',
                isActive: false,
                onTap: _noop,
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.photo_camera,
                label: 'Camera',
                isActive: true,
                onTap: _noop,
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.settings,
                label: 'Settings',
                isActive: false,
                onTap: _noop,
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
