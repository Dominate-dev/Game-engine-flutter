import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_fonts.dart';
import '../../utils/app_url.dart';
import 'app_skeleton.dart';
import 'app_text_view.dart';

/// Shared image — network URL or asset, SVG / PNG / JPG / WebP / GIF.
///
/// Use [size] for a square, or [width] / [height] separately.
/// [radius] rounds corners; [isCircle] clips to an oval.
/// While the image loads, a skeleton is shown by default.
class AppImageView extends StatelessWidget {
  const AppImageView({
    super.key,
    this.imageUrl,
    this.assetPath,
    this.package,
    this.size,
    this.width,
    this.height,
    this.radius = 0,
    this.isCircle = false,
    this.fit = BoxFit.cover,
    this.color,
    this.backgroundColor,
    this.borderWidth = 0,
    this.borderColor,
    this.placeholderText,
    this.alignment = Alignment.center,
    this.showSkeleton = true,
    this.showLoader = false,
    this.skeletonColor,
    this.skeletonHighlight,
  });

  /// Remote image (`http` / `https`).
  final String? imageUrl;

  /// Local asset path, e.g. `assets/images/logo.png`.
  final String? assetPath;

  /// Package that owns [assetPath] (e.g. `coreapp`).
  final String? package;

  /// Square size. Used when [width] / [height] are null.
  final double? size;

  final double? width;
  final double? height;

  /// Corner radius. Ignored when [isCircle] is true.
  final double radius;

  final bool isCircle;
  final BoxFit fit;

  /// Tint (SVG fill / raster color blend).
  final Color? color;

  final Color? backgroundColor;
  final double borderWidth;
  final Color? borderColor;
  final String? placeholderText;
  final Alignment alignment;

  /// Shimmer while the image loads. Default on — same [AppImageView] usage.
  final bool showSkeleton;

  /// Small circular loader instead of the skeleton.
  final bool showLoader;

  /// Skeleton base. Defaults to [AppColors.skeleton].
  final Color? skeletonColor;

  /// Skeleton shimmer line. Defaults to [AppColors.skeletonHighlight].
  final Color? skeletonHighlight;

  double? get _width => width ?? size;
  double? get _height => height ?? size;

  String get _source {
    final url = AppUrl.httpOrNull(imageUrl);
    if (url != null) {
      return url;
    }
    return assetPath?.trim() ?? '';
  }

  bool get _hasSource => _source.isNotEmpty;

  bool get _isNetwork => AppUrl.isHttp(imageUrl);

  bool get _isSvg => _source.toLowerCase().split('?').first.endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    final resolvedRadius = isCircle ? null : (radius > 0 ? radius : null);

    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.transparent,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle || resolvedRadius == null
            ? null
            : BorderRadius.circular(resolvedRadius),
        border: borderWidth > 0
            ? Border.all(
                color: borderColor ?? AppColors.onBackground,
                width: borderWidth,
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (!_hasSource) {
      return _placeholder();
    }
    if (_isSvg) {
      return _buildSvg();
    }
    if (_isNetwork) {
      return _buildNetworkRaster();
    }
    return _buildAssetRaster();
  }

  Widget _buildSvg() {
    final colorFilter = color == null
        ? null
        : ColorFilter.mode(color!, BlendMode.srcIn);

    if (_isNetwork) {
      return SvgPicture.network(
        _source,
        width: _width,
        height: _height,
        fit: fit,
        alignment: alignment,
        colorFilter: colorFilter,
        placeholderBuilder: (_) => _loading(),
      );
    }

    return SvgPicture.asset(
      _source,
      package: package,
      width: _width,
      height: _height,
      fit: fit,
      alignment: alignment,
      colorFilter: colorFilter,
      placeholderBuilder: (_) => _placeholder(),
    );
  }

  Widget _buildNetworkRaster() {
    return Image.network(
      _source,
      fit: fit,
      alignment: alignment,
      color: color,
      width: _width,
      height: _height,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return _loading();
      },
    );
  }

  Widget _buildAssetRaster() {
    return Image.asset(
      _source,
      package: package,
      fit: fit,
      alignment: alignment,
      color: color,
      width: _width,
      height: _height,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return _loading();
      },
    );
  }

  Widget _loading() {
    if (showLoader) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.grey,
          ),
        ),
      );
    }
    if (!showSkeleton) {
      return _placeholder();
    }
    return AppSkeleton(
      width: _width,
      height: _height,
      isCircle: isCircle,
      radius: radius,
      baseColor: skeletonColor,
      highlightColor: skeletonHighlight,
    );
  }

  Widget _placeholder() {
    final fill = backgroundColor ?? Colors.transparent;
    final text = placeholderText ?? '';
    final letter = text.isNotEmpty ? text[0].toUpperCase() : '';
    if (letter.isEmpty) {
      return ColoredBox(color: fill);
    }
    return ColoredBox(
      color: fill,
      child: Center(
        child: AppTextView(
          letter,
          fontWeight: AppFontWeight.bold,
          fontSize: (_height ?? _width ?? 48) * 0.38,
          color: AppColors.onBackground,
        ),
      ),
    );
  }
}
