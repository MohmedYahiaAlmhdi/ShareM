import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/transfer_models.dart';
import 'sharem_theme.dart';

/// A visual discovery map. Positions do not represent physical distances.
class NearbyRadar extends StatefulWidget {
  const NearbyRadar({super.key, required this.peers,
    required this.deviceName, required this.onTap});
  final List<NearbyDevice> peers;
  final String deviceName;
  final ValueChanged<NearbyDevice> onTap;
  @override
  State<NearbyRadar> createState() => _NearbyRadarState();
}

class _NearbyRadarState extends State<NearbyRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this, duration: const Duration(seconds: 5),
  )..repeat();

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, bounds) {
      final side = math.min(bounds.maxWidth, 292.0);
      return Center(child: SizedBox(
        height: side, width: side,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => CustomPaint(
              painter: _RadarPainter(_pulse.value),
            ),
          )),
          Container(
            height: 66, width: 66,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ShareMTheme.teal, Color(0xFF41C8D1)],
                begin: Alignment.topRight, end: Alignment.bottomLeft),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: ShareMTheme.teal.withAlpha(38),
                blurRadius: 20, offset: const Offset(0, 7))],
            ),
            child: const Icon(Icons.swap_horiz_rounded,
              size: 34, color: Colors.white),
          ),
          Positioned(
            top: side / 2 + 39,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: side - 40),
              child: Text(widget.deviceName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 11, color: ShareMTheme.ink)),
            ),
          ),
          for (var i = 0; i < widget.peers.length && i < 8; i++)
            _device(widget.peers[i], i, side),
        ]),
      ));
    });
  }

  Widget _device(NearbyDevice peer, int index, double side) {
    final radians = index * 2.39996 - math.pi / 2;
    final radius = (index.isEven ? .33 : .42) * side;
    final x = side / 2 + math.cos(radians) * radius - 23;
    final y = side / 2 + math.sin(radians) * radius - 23;
    return Positioned(
      left: x, top: y,
      child: Tooltip(
        message: 'إرسال إلى ' + peer.name,
        child: Material(
          color: Colors.white,
          elevation: 2,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () => widget.onTap(peer),
            customBorder: const CircleBorder(),
            child: Semantics(
              button: true, label: peer.name,
              child: const SizedBox(
                width: 46, height: 46,
                child: Icon(Icons.phone_android_rounded,
                  size: 23, color: ShareMTheme.teal)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter(this.phase);
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 5;
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4,
        Paint()
          ..color = i.isEven ? const Color(0xFFB1E1E8)
                             : const Color(0xFFD4EDF1)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke);
    }
    canvas.drawCircle(center, radius * (.92 + phase * .06),
      Paint()
        ..color = ShareMTheme.mint.withAlpha(((1-phase) * 75).round())
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter other) =>
    other.phase != phase;
}
