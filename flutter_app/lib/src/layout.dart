// Breakpoints (Material 3 window size classes). Every screen adapts to these:
//   compact  < 600   phones in portrait  → bottom navigation, single column
//   medium   < 1040  phones in landscape, small tablets → navigation rail
//   expanded ≥ 1040  large tablets, desktop, browser → extended rail, two panes

import 'dart:math' as math;

import 'package:flutter/material.dart';

enum SizeClass { compact, medium, expanded }

SizeClass sizeClassOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return SizeClass.compact;
  if (w < 1040) return SizeClass.medium;
  return SizeClass.expanded;
}

/// Phones in landscape and other short windows.
bool isShort(BuildContext context) => MediaQuery.sizeOf(context).height < 560;

/// Scrolling page body: content is centred and capped at [maxWidth] so lines
/// never get too long on wide screens, with a 20px gutter on small ones.
class ScreenList extends StatelessWidget {
  const ScreenList({super.key, required this.children, this.maxWidth = 640, this.bottom});

  final List<Widget> children;
  final double maxWidth;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    // leave room for the floating + button above the bottom bar on phones
    final pad = bottom ?? (sizeClassOf(context) == SizeClass.compact ? 96.0 : 32.0);
    return LayoutBuilder(builder: (context, c) {
      final side = math.max(20.0, (c.maxWidth - maxWidth) / 2);
      return ListView(padding: EdgeInsets.fromLTRB(side, 14, side, pad), children: children);
    });
  }
}
