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

/// On desktop the app is a workspace, not a stretched phone: pages use the window up to this width.
const desktopMaxWidth = 1680.0;

bool isDesktop(BuildContext context) => sizeClassOf(context) == SizeClass.expanded;

/// Scrolling page body: content is centred and capped at [maxWidth] so lines never get too long
/// on phones and tablets (20px gutter); on desktop it fills the window ([desktopMaxWidth], 40px gutter).
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
      final desktop = isDesktop(context);
      final side = math.max(desktop ? 40.0 : 20.0, (c.maxWidth - (desktop ? desktopMaxWidth : maxWidth)) / 2);
      return ListView(padding: EdgeInsets.fromLTRB(side, 14, side, pad), children: children);
    });
  }
}

/// Two side-by-side columns on desktop, one stacked column everywhere else.
class TwoPane extends StatelessWidget {
  const TwoPane({super.key, required this.left, required this.right, this.leftFlex = 1, this.rightFlex = 1});
  final List<Widget> left, right;
  final int leftFlex, rightFlex;

  @override
  Widget build(BuildContext context) {
    Widget col(List<Widget> c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: c);
    if (!isDesktop(context)) return col([...left, ...right]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: leftFlex, child: col(left)),
      const SizedBox(width: 56),
      Expanded(flex: rightFlex, child: col(right)),
    ]);
  }
}
