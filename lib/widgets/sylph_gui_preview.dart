import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/sylph_instance_node.dart';

/// Renders a tree of [SylphInstanceNode] (parsed from the mock Roblox GUI
/// state dumped by the Luau VM) as real Flutter widgets, so a script that
/// builds a ScreenGui full of Frames/TextButtons/TextLabels can be
/// previewed live instead of just printing to a log.
///
/// [onFireEvent] is called with `(instanceId, eventName)` whenever the user
/// interacts with something that has a Roblox-style event connected to it
/// (currently just TextButton taps → "MouseButton1Click"). The caller is
/// expected to invoke the corresponding Luau callback via
/// `LuauRunnerService.fireEvent` and then refresh the tree from a new
/// [LuauRunnerService.snapshot] call, since the callback may have mutated
/// properties (e.g. changed a label's Text).
class SylphGuiPreview extends StatelessWidget {
  final List<SylphInstanceNode> roots;
  final void Function(int instanceId, String eventName) onFireEvent;

  const SylphGuiPreview({
    super.key,
    required this.roots,
    required this.onFireEvent,
  });

  @override
  Widget build(BuildContext context) {
    if (roots.isEmpty) {
      return const SizedBox.shrink();
    }
    // Roblox lets a script parent multiple ScreenGuis; stack them in
    // z-order (later = on top), same as Roblox's rendering order.
    return Stack(
      children: [
        for (final root in roots)
          if (root.visible) _ScreenGuiView(node: root, onFireEvent: onFireEvent),
      ],
    );
  }
}

class _ScreenGuiView extends StatelessWidget {
  final SylphInstanceNode node;
  final void Function(int instanceId, String eventName) onFireEvent;

  const _ScreenGuiView({required this.node, required this.onFireEvent});

  @override
  Widget build(BuildContext context) {
    // A ScreenGui itself has no visual size/position of its own — it's a
    // container whose direct children are positioned relative to the
    // whole screen. We just lay its children out absolutely, filling
    // whatever space the parent (the preview panel) gives us.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (final child in node.children)
              if (child.visible)
                _PositionedInstance(
                  node: child,
                  parentWidth: constraints.maxWidth,
                  parentHeight: constraints.maxHeight,
                  onFireEvent: onFireEvent,
                ),
          ],
        );
      },
    );
  }
}

/// Wraps [_InstanceView] in a [Positioned] using the node's Roblox-style
/// UDim2 Size/Position resolved against the parent's actual pixel size —
/// this is what gives free-form (non-linear-layout) placement matching how
/// Roblox GUIs normally work.
class _PositionedInstance extends StatelessWidget {
  final SylphInstanceNode node;
  final double parentWidth;
  final double parentHeight;
  final void Function(int instanceId, String eventName) onFireEvent;

  const _PositionedInstance({
    required this.node,
    required this.parentWidth,
    required this.parentHeight,
    required this.onFireEvent,
  });

  @override
  Widget build(BuildContext context) {
    final size = node.size;
    final position = node.position;

    final width = size?.resolveWidth(parentWidth) ?? 100.0;
    final height = size?.resolveHeight(parentHeight) ?? 40.0;
    final left = position?.resolveWidth(parentWidth) ?? 0.0;
    final top = position?.resolveHeight(parentHeight) ?? 0.0;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: _InstanceView(
        node: node,
        onFireEvent: onFireEvent,
      ),
    );
  }
}

/// Renders a single instance's own visual (background, text, image) plus
/// its children, laid out absolutely within its own bounds.
class _InstanceView extends StatelessWidget {
  final SylphInstanceNode node;
  final void Function(int instanceId, String eventName) onFireEvent;

  const _InstanceView({required this.node, required this.onFireEvent});

  @override
  Widget build(BuildContext context) {
    switch (node.className) {
      case 'TextLabel':
        return _decoratedBox(child: _centeredText(context));
      case 'TextButton':
        return _decoratedBox(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onFireEvent(node.id, 'MouseButton1Click'),
              child: _centeredText(context),
            ),
          ),
        );
      case 'TextBox':
        return _decoratedBox(
          child: Center(
            child: Text(
              node.text?.isNotEmpty == true
                  ? node.text!
                  : (node.props['PlaceholderText'] as String? ?? ''),
              style: GoogleFonts.inter(
                fontSize: node.textSize ?? 14,
                color: node.textColor3?.toColor() ?? Colors.black54,
              ),
            ),
          ),
        );
      case 'ImageLabel':
      case 'ImageButton':
        // No real Roblox asset resolution here (that would need a working
        // rbxassetid:// -> URL proxy) — show a placeholder so the layout
        // is still visible instead of silently rendering nothing.
        return _decoratedBox(
          child: Icon(Icons.image_outlined, color: Colors.white.withValues(alpha: 0.35)),
        );
      case 'Frame':
      case 'ScrollingFrame':
      default:
        // Frame, ScrollingFrame, Folder, or anything unrecognized: just a
        // container for its children, absolutely positioned within it.
        return _decoratedBox(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: node.className == 'ScrollingFrame' ? Clip.hardEdge : Clip.none,
                children: [
                  for (final child in node.children)
                    if (child.visible)
                      _PositionedInstance(
                        node: child,
                        parentWidth: constraints.maxWidth,
                        parentHeight: constraints.maxHeight,
                        onFireEvent: onFireEvent,
                      ),
                ],
              );
            },
          ),
        );
    }
  }

  Widget _centeredText(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          node.text ?? '',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: node.textSize ?? 14,
            fontWeight: node.className == 'TextButton' ? FontWeight.w600 : FontWeight.w400,
            color: node.textColor3?.toColor() ?? Colors.black87,
          ),
        ),
      ),
    );
  }

  /// UICorner (like UIListLayout, UIPadding) is a Roblox "modifier"
  /// instance — created separately and parented into the Frame/Button it
  /// affects, rather than being a direct property of that instance. So we
  /// look for a UICorner child instead of reading a CornerRadius prop that
  /// would never actually be set on `node` itself.
  SylphUDim? get _cornerRadiusFromChild {
    for (final child in node.children) {
      if (child.className == 'UICorner') {
        final encoded = child.props['CornerRadius'] as String?;
        return SylphInstanceNode.parseUDim(encoded);
      }
    }
    return null;
  }

  Widget _decoratedBox({required Widget child}) {
    final bg = node.backgroundColor3?.toColor(
          opacity: 1.0 - node.backgroundTransparency.clamp(0.0, 1.0),
        ) ??
        Colors.transparent;
    final radius = _cornerRadiusFromChild?.resolve(0) ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
      ),
      clipBehavior: radius > 0 ? Clip.antiAlias : Clip.none,
      child: child,
    );
  }
}
