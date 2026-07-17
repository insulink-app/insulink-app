import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The square both phases of [Libre3NfcScanSheet] put their icon in: wide enough
/// for the pulse rings to expand into, and identical for both so the sheet keeps
/// its height when the scan lands.
const double libre3IconArea = 128;

/// The disc the icon itself sits on, inside [libre3IconArea].
const double _discSize = 80;

/// "Hold the sensor to your phone": an NFC icon on a disc, wrapped in two rings
/// that expand outward and fade on a loop.
class Libre3PulsingIcon extends StatefulWidget {
  const Libre3PulsingIcon({super.key});

  @override
  State<Libre3PulsingIcon> createState() => _Libre3PulsingIconState();
}

class _Libre3PulsingIconState extends State<Libre3PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: libre3IconArea,
      height: libre3IconArea,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            // Two rings half a cycle apart, so one is always mid-flight.
            _ring(scheme, _pulse.value),
            _ring(scheme, (_pulse.value + 0.5) % 1.0),
            child!,
          ],
        ),
        child: _Libre3IconDisc(
          icon: PhosphorIconsBold.scan,
          iconSize: 40,
          alpha: 0.12,
        ),
      ),
    );
  }

  /// One expanding ring: starts at the disc and fades out as it reaches the edge
  /// of [libre3IconArea].
  Widget _ring(ColorScheme scheme, double progress) {
    final size = _discSize + progress * (libre3IconArea - _discSize);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.primary.withValues(alpha: (1 - progress) * 0.4),
          width: 2,
        ),
      ),
    );
  }
}

/// "Scanned": a check mark that scales + fades in once, marking the switch to
/// success. Claims the same box as [Libre3PulsingIcon] it replaces.
class Libre3CheckIcon extends StatelessWidget {
  const Libre3CheckIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: libre3IconArea,
      height: libre3IconArea,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          ),
          child: _Libre3IconDisc(
            icon: PhosphorIconsBold.check,
            iconSize: 44,
            alpha: 0.14,
          ),
        ),
      ),
    );
  }
}

/// The tinted circle both phase icons sit on.
class _Libre3IconDisc extends StatelessWidget {
  const _Libre3IconDisc({
    required this.icon,
    required this.iconSize,
    required this.alpha,
  });

  final IconData icon;
  final double iconSize;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: _discSize,
      height: _discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary.withValues(alpha: alpha),
      ),
      child: Icon(icon, size: iconSize, color: primary),
    );
  }
}
