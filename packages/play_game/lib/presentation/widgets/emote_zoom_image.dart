import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';

class EmoteZoomImage extends StatefulWidget {
  const EmoteZoomImage({
    super.key,
    required this.imageUrl,
    this.size = 36,
  });

  final String imageUrl;
  final double size;

  @override
  State<EmoteZoomImage> createState() => _EmoteZoomImageState();
}

class _EmoteZoomImageState extends State<EmoteZoomImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scale = Tween<double>(begin: 0.2, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(EmoteZoomImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: AppImageView(
        imageUrl: widget.imageUrl,
        size: widget.size,
        fit: BoxFit.contain,
      ),
    );
  }
}
