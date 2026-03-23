import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // thêm

class LandmarkPainter extends CustomPainter {
  final List<double> landmarks;

  LandmarkPainter(this.landmarks);

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty || landmarks.length != 96) return;

    final paintPoint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.fill;

    final paintLine = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final points = <Offset>[];
    for (int i = 0; i < landmarks.length; i += 2) {
      final x = landmarks[i] * size.width;
      final y = landmarks[i + 1] * size.height;
      points.add(Offset(x, y));
    }

    _drawHand(canvas, points.sublist(6, 27), paintLine, paintPoint);
    _drawHand(canvas, points.sublist(27, 48), paintLine, paintPoint);
  }

  void _drawHand(
    Canvas canvas,
    List<Offset> handPoints,
    Paint paintLine,
    Paint paintPoint,
  ) {
    if (handPoints[0].dx == 0 && handPoints[0].dy == 0) return;

    final connections = [
      [0, 1],
      [1, 2],
      [2, 3],
      [3, 4],
      [0, 5],
      [5, 6],
      [6, 7],
      [7, 8],
      [9, 10],
      [10, 11],
      [11, 12],
      [13, 14],
      [14, 15],
      [15, 16],
      [17, 18],
      [18, 19],
      [19, 20],
      [5, 9],
      [9, 13],
      [13, 17],
      [0, 17],
    ];

    for (var conn in connections) {
      canvas.drawLine(handPoints[conn[0]], handPoints[conn[1]], paintLine);
    }
    for (var p in handPoints) {
      canvas.drawCircle(p, 3, paintPoint);
    }
  }

  @override
  bool shouldRepaint(covariant LandmarkPainter oldDelegate) =>
      !listEquals(oldDelegate.landmarks, landmarks);
}
