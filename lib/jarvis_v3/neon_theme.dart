import 'package:flutter/material.dart';

/// Palette of the approved amber-neon JARVIS concept.
abstract final class NeonColors {
  static const background = Color(0xFF000000);
  static const amber = Color(0xFFFFB627);
  static const gold = Color(0xFFFFD66B);
  static const amberDeep = Color(0xFFB86E00);
  static const cyan = Color(0xFF2EE6FF);
  static const teal = Color(0xFF14C8C0);

  /// Text colours chosen for contrast on the translucent dark bubbles
  /// (both above 12:1 against #0B0B0B).
  static const userText = Color(0xFFE6FDFF);
  static const jarvisText = Color(0xFFFFF4DC);
  static const error = Color(0xFFFF6B6B);
}

/// The amber "JARVIS" wordmark used in the header and the introduction.
class JarvisWordmark extends StatelessWidget {
  const JarvisWordmark({super.key, this.size = 22, this.glow = 1.0});
  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) => Text(
        'JARVIS',
        key: const ValueKey('v3-title'),
        style: TextStyle(
          color: NeonColors.gold,
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: size * 0.32,
          shadows: [
            Shadow(color: NeonColors.amber.withValues(alpha: 0.9 * glow), blurRadius: 10),
            Shadow(color: NeonColors.amberDeep.withValues(alpha: 0.8 * glow), blurRadius: 26),
          ],
        ),
      );
}
