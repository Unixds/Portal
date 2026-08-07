import 'package:flutter/material.dart';

/// Custom Vector Icon depicting two round circular overlapping speech bubbles
/// matching the exact visual reference image.
class DoubleChatBubbleIcon extends StatelessWidget {
  final Color color;
  final double size;

  const DoubleChatBubbleIcon({
    super.key,
    required this.color,
    this.size = 22.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _DoubleChatBubblePainter(color: color),
      ),
    );
  }
}

class _DoubleChatBubblePainter extends CustomPainter {
  final Color color;

  _DoubleChatBubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 1. Back Bubble (Upper Right Circle)
    final backPath = Path()
      ..addOval(Rect.fromCircle(center: const Offset(15.2, 10.2), radius: 6.2))
      ..moveTo(19.2, 13.5)
      ..quadraticBezierTo(21.2, 17.5, 21.8, 18.2)
      ..quadraticBezierTo(17.8, 17.5, 16.5, 16.0)
      ..close();

    // 2. Front Bubble (Lower Left Circle)
    final frontPath = Path()
      ..addOval(Rect.fromCircle(center: const Offset(9.8, 9.8), radius: 7.2))
      ..moveTo(4.8, 14.2)
      ..quadraticBezierTo(2.2, 18.8, 1.8, 19.5)
      ..quadraticBezierTo(6.2, 18.2, 7.8, 16.5)
      ..close();

    // Draw back bubble
    canvas.drawPath(backPath, paint);

    // Draw dark gap border around front bubble to separate from back bubble cleanly
    final gapPaint = Paint()
      ..color = const Color(0xFF141416)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..isAntiAlias = true;
    canvas.drawPath(frontPath, gapPaint);

    // Draw front bubble
    canvas.drawPath(frontPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DoubleChatBubblePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
