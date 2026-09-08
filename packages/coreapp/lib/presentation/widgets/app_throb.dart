import 'package:flutter/material.dart';

class AppThrob extends StatefulWidget {
  const AppThrob({
    super.key,
    required this.child,
    this.count = 1,
    this.duration = const Duration(milliseconds: 250),
    this.scale = 1.05,
  });

  final Widget child;
  final int count;
  final Duration duration;
  final double scale;

  @override
  State<AppThrob> createState() => _AppThrobState();
}

class _AppThrobState extends State<AppThrob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  int _completed = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 1, end: widget.scale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.addStatusListener(_onStatus);
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _completed++;
      _controller.reverse();
    } else if (status == AnimationStatus.dismissed &&
        _completed < widget.count) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: widget.child,
    );
  }
}
