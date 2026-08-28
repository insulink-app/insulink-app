import 'package:flutter/material.dart';

/// A scroll area with a header pinned above it that fades and rises out of the
/// way as the content is scrolled up into its place.
///
/// Shared by both device pages so the sensor and the pump behave identically —
/// the fade distances, the rise, and the snap are one implementation rather than
/// two that drift apart.
class PinnedHeaderScroll extends StatefulWidget {
  const PinnedHeaderScroll({
    super.key,
    required this.header,
    required this.child,
  });

  /// Pinned at the top. Its rendered height is measured, so it may be any size.
  final Widget header;

  /// Scrolls underneath the header.
  final Widget child;

  @override
  State<PinnedHeaderScroll> createState() => _PinnedHeaderScrollState();
}

class _PinnedHeaderScrollState extends State<PinnedHeaderScroll> {
  /// The header reaches full transparency after this many pixels — a longer
  /// distance than the scroll it tracks, so the fade feels gentle.
  static const double _fadeDistance = 160;

  /// How far the header drifts upward as it fades, so it doesn't just dissolve
  /// in place but slides out of the way.
  static const double _riseDistance = 40;

  /// Gap between the pinned header and the scrolling content. Kept at least
  /// [_fadeDistance] so the header has fully faded before the content scrolls up
  /// into its place (no overlap).
  static const double _gap = 80;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Reads the header's rendered height after layout and reserves that much
  /// space above the scrolling content, so nothing starts hidden. Runs each
  /// frame but only rebuilds on change.
  void _measureHeader() {
    final height = _headerKey.currentContext?.size?.height;
    if (height != null && height != _headerHeight) {
      setState(() => _headerHeight = height);
    }
  }

  /// Snaps to one of two resting positions once the user lets go: fully showing
  /// the header, or fully scrolled past it. Crossing [_fadeDistance] commits to
  /// the collapsed position for a snappy feel instead of leaving it half-faded.
  bool _snapScroll() {
    if (!_scroll.hasClients) {
      return false;
    }
    final snapTarget = (_headerHeight + _gap).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    final offset = _scroll.offset;
    if (snapTarget <= 0 || offset >= snapTarget) {
      return false;
    }
    final target = offset >= _fadeDistance ? snapTarget : 0.0;
    if ((offset - target).abs() >= 1) {
      _animateTo(target);
    }
    return false;
  }

  void _animateTo(double target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
    return Stack(
      children: [
        Positioned.fill(child: _scrollContent()),
        _pinnedHeader(),
      ],
    );
  }

  Widget _scrollContent() {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) => _snapScroll(),
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(
            top: _headerHeight > 0 ? _headerHeight + _gap : 0,
          ),
          child: widget.child,
        ),
      ),
    );
  }

  Widget _pinnedHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _scroll,
        builder: (context, child) => _fade(child!),
        child: KeyedSubtree(key: _headerKey, child: widget.header),
      ),
    );
  }

  Widget _fade(Widget child) {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final progress = (offset / _fadeDistance).clamp(0.0, 1.0);
    final opacity = 1 - progress;
    // Once mostly faded, let touches reach the content below.
    return IgnorePointer(
      ignoring: opacity < 0.5,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, -progress * _riseDistance),
          child: child,
        ),
      ),
    );
  }
}
