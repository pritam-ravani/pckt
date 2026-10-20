import 'package:flutter/material.dart';

import '../core/theme/palette.dart';

/// The Pckt app icon: a white "P" whose bowl holds a mint coin, on the brand
/// gradient. Same geometry and colours as the launcher icon
/// (tool/gen_brand_assets.js, assets/branding/pckt-icon.svg).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.28),
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter()),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  // Unit-square geometry, shared with the icon generator.
  static const stemX = 0.383, top = 0.305, bottom = 0.705, bowlBottom = 0.535;
  static const bowlCx = 0.497, bowlR = 0.115, stroke = 0.082, coinR = 0.043;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B7CF6), Color(0xFF5B4BE0), Color(0xFF2A2380)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    canvas.save();
    // Like the launcher, which shows the inner 72dp of the 108dp canvas.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide * 1.4);
    canvas.translate(-0.5, -0.5);

    const cy = (top + bowlBottom) / 2;
    final p = Path()
      ..moveTo(stemX, bottom)
      ..lineTo(stemX, top)
      ..lineTo(bowlCx, top)
      ..arcToPoint(const Offset(bowlCx, bowlBottom), radius: const Radius.circular(bowlR))
      ..lineTo(stemX, bowlBottom);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    canvas.drawCircle(const Offset(bowlCx, cy), coinR, Paint()..color = Palette.mint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
