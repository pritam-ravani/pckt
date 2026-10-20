import 'package:flutter/material.dart';

import '../core/theme/palette.dart';

/// The Pckt mark: a violet "P" whose bowl holds a mint coin. Same geometry
/// as the launcher icon (tool/gen_brand_assets.js).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _MarkPainter()));
}

class _MarkPainter extends CustomPainter {
  // Unit-square geometry, shared with the icon generator.
  static const stemX = 0.385, top = 0.30, bottom = 0.72, bowlBottom = 0.54;
  static const bowlCx = 0.505, bowlR = 0.12, stroke = 0.085, coinR = 0.046;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    // The mark spans roughly 0.34–0.69 × 0.26–0.76; centre and enlarge it.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s * 1.5);
    canvas.translate(-0.515, -0.51);

    const cy = (top + bowlBottom) / 2;
    final p = Path()
      ..moveTo(stemX, bottom)
      ..lineTo(stemX, top)
      ..lineTo(bowlCx, top)
      ..arcToPoint(const Offset(bowlCx, bowlBottom), radius: const Radius.circular(bowlR))
      ..lineTo(stemX, bowlBottom);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF9D90FF), Color(0xFF6D5DF6)],
      ).createShader(const Rect.fromLTRB(0.3, top, 0.7, bottom));
    canvas.drawPath(p, paint);
    canvas.drawCircle(const Offset(bowlCx, cy), coinR, Paint()..color = Palette.mint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
