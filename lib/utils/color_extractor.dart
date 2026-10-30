import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

/// 提取图片主色调，用于播放页背景渐变
Future<Color?> extractDominantColor(String? imageUrl) async {
  if (imageUrl == null || imageUrl.isEmpty) return null;
  try {
    final provider = CachedNetworkImageProvider(imageUrl);
    final palette = await PaletteGenerator.fromImageProvider(
      provider,
      size: const Size(100, 100),
      maximumColorCount: 8,
    );
    return palette.dominantColor?.color;
  } catch (_) {
    return null;
  }
}
