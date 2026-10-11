import 'package:flutter/material.dart';

/// Crisp, standalone widget that draws the official Google 4-color 'G' logo
/// via CustomPainter with zero network or external asset dependencies.
class GoogleLogoWidget extends StatelessWidget {
  final double size;
  const GoogleLogoWidget({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width / 2;
    final double strokeWidth = size.width * 0.22;
    final rect = Rect.fromCircle(
      center: Offset(center, center),
      radius: center - (strokeWidth / 2),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Blue: top-right arc
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.75, 1.0, false, paint);

    // Green: bottom-right arc
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.25, 1.45, false, paint);

    // Yellow: bottom-left arc
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 1.7, 1.4, false, paint);

    // Red: top-left arc
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.1, 1.4, false, paint);

    // Center horizontal blue crossbar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final barRect = Rect.fromLTRB(
      center - 1,
      center - (strokeWidth / 2),
      size.width,
      center + (strokeWidth / 2),
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Standard, beautifully styled Google Sign-In button following Material Design.
class GoogleSignInButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const GoogleSignInButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const GoogleLogoWidget(size: 20),
                const SizedBox(width: 12),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
    );
  }
}
