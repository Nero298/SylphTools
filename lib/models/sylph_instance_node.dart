import 'dart:convert';
import 'dart:ui';

/// A parsed `UDim2` value (Roblox-style 2D size/position: scale + offset
/// per axis). The GUI bootstrap (sylph_gui_bootstrap.lua) encodes these as
/// a string like `"UDim2:xScale,xOffset,yScale,yOffset"` when it serializes
/// props to JSON — see [SylphProp.parse] for the decode side.
class SylphUDim2 {
  final double xScale;
  final double xOffset;
  final double yScale;
  final double yOffset;

  const SylphUDim2(this.xScale, this.xOffset, this.yScale, this.yOffset);

  /// Resolves this UDim2 to actual device pixels given the size of the
  /// parent container, matching how Roblox composes scale + offset.
  double resolveWidth(double parentWidth) => xScale * parentWidth + xOffset;
  double resolveHeight(double parentHeight) => yScale * parentHeight + yOffset;
}

/// A parsed `UDim` value (single-axis scale + offset), used for things like
/// UIListLayout padding or UICorner radius.
class SylphUDim {
  final double scale;
  final double offset;

  const SylphUDim(this.scale, this.offset);

  double resolve(double parentSize) => scale * parentSize + offset;
}

/// A parsed `Color3` value. The bootstrap encodes these as 0-255 components
/// already (see `newColor3`'s `__tostring` in sylph_gui_bootstrap.lua),
/// even though Roblox's real Color3 is 0-1 floats — this keeps the Dart
/// side simple since Flutter's Color is 0-255 too.
class SylphColor3 {
  final int r;
  final int g;
  final int b;

  const SylphColor3(this.r, this.g, this.b);

  Color toColor({double opacity = 1.0}) =>
      Color.fromRGBO(r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), opacity);
}

/// A single node in the mock GUI tree, corresponding to one Roblox
/// `Instance` created via `Instance.new(...)` in the user's script.
class SylphInstanceNode {
  final int id;
  final String className;
  final Map<String, dynamic> props;
  final List<SylphInstanceNode> children;

  const SylphInstanceNode({
    required this.id,
    required this.className,
    required this.props,
    required this.children,
  });

  String get name => (props['Name'] as String?) ?? className;
  bool get visible => (props['Visible'] as bool?) ?? true;

  String? get text => props['Text'] as String?;
  double? get textSize => (props['TextSize'] as num?)?.toDouble();

  double get backgroundTransparency =>
      (props['BackgroundTransparency'] as num?)?.toDouble() ?? 0.0;

  SylphUDim2? get size => parseUDim2(props['Size'] as String?);
  SylphUDim2? get position => parseUDim2(props['Position'] as String?);
  SylphColor3? get backgroundColor3 => parseColor3(props['BackgroundColor3'] as String?);
  SylphColor3? get textColor3 => parseColor3(props['TextColor3'] as String?);

  static SylphUDim2? parseUDim2(String? encoded) {
    if (encoded == null || !encoded.startsWith('UDim2:')) return null;
    final parts = encoded.substring('UDim2:'.length).split(',');
    if (parts.length != 4) return null;
    final nums = parts.map((p) => double.tryParse(p) ?? 0.0).toList();
    return SylphUDim2(nums[0], nums[1], nums[2], nums[3]);
  }

  static SylphUDim? parseUDim(String? encoded) {
    if (encoded == null || !encoded.startsWith('UDim:')) return null;
    final parts = encoded.substring('UDim:'.length).split(',');
    if (parts.length != 2) return null;
    final nums = parts.map((p) => double.tryParse(p) ?? 0.0).toList();
    return SylphUDim(nums[0], nums[1]);
  }

  static SylphColor3? parseColor3(String? encoded) {
    if (encoded == null || !encoded.startsWith('Color3:')) return null;
    final parts = encoded.substring('Color3:'.length).split(',');
    if (parts.length != 3) return null;
    final nums = parts.map((p) => double.tryParse(p) ?? 0.0).toList();
    return SylphColor3(nums[0].round(), nums[1].round(), nums[2].round());
  }

  factory SylphInstanceNode.fromMap(Map<String, dynamic> map) {
    final childrenRaw = map['children'] as List<dynamic>? ?? const [];
    return SylphInstanceNode(
      id: (map['id'] as num?)?.toInt() ?? 0,
      className: map['className'] as String? ?? 'Unknown',
      props: (map['props'] as Map<String, dynamic>?) ?? const {},
      children: childrenRaw
          .map((c) => SylphInstanceNode.fromMap(c as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Parses the raw JSON string returned by `LuauRunnerService.snapshot()`
  /// into a forest of top-level nodes (everything directly parented under
  /// PlayerGui — typically one or more ScreenGuis).
  static List<SylphInstanceNode> parseForest(String json) {
    try {
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .map((n) => SylphInstanceNode.fromMap(n as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
