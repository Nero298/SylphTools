/// Represents a downloadable/loadable AI model from the catalog, OR a
/// hosted model (e.g. Piwi AI) that opens in an in-app WebView instead of
/// being downloaded — see [isHosted] / [webviewUrl].
class AiModelInfo {
  final String id;
  final String name;
  final String filename;
  final String url;
  final double sizeGb;
  final int minRamGb;
  final String label;        // UNCENSORED / STANDARD / CUSTOM
  final String badge;        // RECOMMENDED, HERETIC, etc.
  final String systemPrompt;
  final bool recommended;

  /// True for models that run on a remote host rather than on-device.
  /// Hosted entries skip the download/RAM/load flow entirely and instead
  /// show an "Open" action that launches [webviewUrl] in an in-app WebView.
  final bool isHosted;

  /// URL to open in a WebView when this is a hosted model. Ignored for
  /// regular (on-device) models.
  final String? webviewUrl;

  /// Extra small tags shown alongside the label/badge — e.g. "QUEUE ~10",
  /// "FREE", "NO LOGIN". Purely informational.
  final List<String> tags;

  const AiModelInfo({
    required this.id,
    required this.name,
    required this.filename,
    required this.url,
    required this.sizeGb,
    required this.minRamGb,
    required this.label,
    required this.badge,
    required this.systemPrompt,
    this.recommended = false,
    this.isHosted = false,
    this.webviewUrl,
    this.tags = const [],
  });

  factory AiModelInfo.fromJson(Map<String, dynamic> json) {
    return AiModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      filename: json['filename'] as String? ?? '',
      url: json['url'] as String? ?? '',
      sizeGb: (json['sizeGb'] as num?)?.toDouble() ?? 0.0,
      minRamGb: (json['minRamGb'] as num?)?.toInt() ?? 0,
      label: json['label'] as String? ?? 'STANDARD',
      badge: json['badge'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      recommended: json['recommended'] as bool? ?? false,
      isHosted: json['isHosted'] as bool? ?? false,
      webviewUrl: json['webviewUrl'] as String?,
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filename': filename,
        'url': url,
        'sizeGb': sizeGb,
        'minRamGb': minRamGb,
        'label': label,
        'badge': badge,
        'systemPrompt': systemPrompt,
        'recommended': recommended,
        'isHosted': isHosted,
        'webviewUrl': webviewUrl,
        'tags': tags,
      };

  bool get isUncensored => label == 'UNCENSORED';
  bool get isStandard => label == 'STANDARD';
  bool get isCustom => label == 'CUSTOM';
}
