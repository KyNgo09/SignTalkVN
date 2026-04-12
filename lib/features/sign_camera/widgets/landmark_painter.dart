import 'package:flutter/material.dart';
import 'dart:ui' as ui;

// ═══════════════════════════════════════════════════════════════
// Painter vẽ skeleton — chỉ repaint, KHÔNG rebuild widget tree
// ═══════════════════════════════════════════════════════════════
// Dùng ChangeNotifier qua tham số `repaint` của CustomPaint
// → khi gọi notifyListeners(), chỉ canvas.drawXxx() chạy lại
// → widget tree giữ nguyên → hiệu suất tối đa
class SmoothLandmarkPainter extends ChangeNotifier implements CustomPainter {
  List<double> _landmarks = [];

  void update(List<double> landmarks) {
    _landmarks = landmarks;
    notifyListeners(); // Chỉ trigger repaint, không rebuild widget
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_landmarks.isEmpty || _landmarks.length != 96) return;

    final points = <Offset>[];
    for (int i = 0; i < _landmarks.length; i += 2) {
      final x = _landmarks[i] * size.width;
      final y = _landmarks[i + 1] * size.height;
      points.add(Offset(x, y));
    }

    // Layout: [0-5] Pose, [6-26] Left Hand, [27-47] Right Hand
    _drawPose(canvas, points);
    _drawHand(canvas, points, 6, 27);
    _drawHand(canvas, points, 27, 48);
  }

  void _drawPose(Canvas canvas, List<Offset> points) {
    if (_isZero(points[0]) && _isZero(points[1])) return;

    final paintBone = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final paintJoint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;

    const connections = [[0,1],[0,2],[2,4],[1,3],[3,5]];
    for (final c in connections) {
      if (!_isZero(points[c[0]]) && !_isZero(points[c[1]])) {
        canvas.drawLine(points[c[0]], points[c[1]], paintBone);
      }
    }
    for (int i = 0; i < 6; i++) {
      if (!_isZero(points[i])) {
        canvas.drawCircle(points[i], i < 2 ? 5.0 : 3.5, paintJoint);
      }
    }
  }

  void _drawHand(Canvas canvas, List<Offset> all, int start, int end) {
    final hp = all.sublist(start, end);
    if (_isZero(hp[0])) return;

    final paintLine = Paint()
      ..color = const Color(0xFFFFD740)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final paintDot = Paint()
      ..color = const Color(0xFFFF5252)
      ..style = PaintingStyle.fill;

    const conn = [
      [0,1],[1,2],[2,3],[3,4],
      [0,5],[5,6],[6,7],[7,8],
      [9,10],[10,11],[11,12],
      [13,14],[14,15],[15,16],
      [17,18],[18,19],[19,20],
      [5,9],[9,13],[13,17],[0,17],
    ];
    for (final c in conn) {
      if (!_isZero(hp[c[0]]) && !_isZero(hp[c[1]])) {
        canvas.drawLine(hp[c[0]], hp[c[1]], paintLine);
      }
    }
    for (final p in hp) {
      if (!_isZero(p)) canvas.drawCircle(p, 2.5, paintDot);
    }
  }

  bool _isZero(Offset p) => p.dx == 0 && p.dy == 0;

  // ── CustomPainter interface ──
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false; // Dùng notifyListeners thay thế

  @override
  bool? hitTest(Offset position) => null;

  @override
  SemanticsBuilderCallback? get semanticsBuilder => null;

  @override
  bool shouldRebuildSemantics(covariant CustomPainter oldDelegate) => false;
}
