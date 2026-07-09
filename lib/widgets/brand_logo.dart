import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.pngAssetPath = 'assets/branding/logo.png',
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
  });

  final String pngAssetPath;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      pngAssetPath,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
    );
  }
}

