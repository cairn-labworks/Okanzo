/// Semantic icon category for a [ReleaseHighlight].
///
/// Mapped exhaustively to Material icons in `lib/ui/components/type_icons.dart`
/// so the domain layer stays free of Flutter UI imports while guaranteeing at
/// compile time that every highlight has a feature-specific icon.
enum ReleaseHighlightIcon {
  language,
  exchanges,
  crypto,
  releaseNotes,
  portfolio,
  statistics,
  security,
  backup,
  currency,
  theme,
  assets,
  liabilities,
}

class ReleaseHighlight {
  const ReleaseHighlight({
    required this.icon,
    required this.title,
    required this.description,
  });

  final ReleaseHighlightIcon icon;
  final String title;
  final String description;
}

class ReleaseNotes {
  const ReleaseNotes({required this.version, required this.highlights});

  final String version;
  final List<ReleaseHighlight> highlights;
}

/// Versioned release highlights shown in the "What's new" dialog after an
/// install or update, and from Settings → About.
class AppReleaseNotes {
  const AppReleaseNotes._();

  static const String currentVersion = '1.3.0';

  static const List<ReleaseNotes> all = <ReleaseNotes>[
    ReleaseNotes(
      version: '1.3.0',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.language,
          title: '21 app languages',
          description: 'Choose your preferred app language in Settings, or follow your device language automatically.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.exchanges,
          title: 'Global stock exchanges',
          description: 'Look up stocks and funds across US, European, and Asian exchanges, and customize your preferred exchange list.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.crypto,
          title: 'Smarter crypto & market quotes',
          description: 'Enter bare crypto tickers like BTC or ETH, with automatic conversion from the quote currency into your holding currency.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.releaseNotes,
          title: "What's new on update",
          description: 'See key release highlights after updating Okanzo, or reopen them anytime from Settings.',
        ),
      ],
    ),
  ];

  static ReleaseNotes get current => forVersion(currentVersion) ?? all.first;

  static ReleaseNotes? forVersion(
    String version, {
    List<ReleaseNotes> releases = all,
  }) {
    final String normalized = normalizeVersion(version);
    if (normalized.isEmpty) return null;
    for (final ReleaseNotes entry in releases) {
      if (normalizeVersion(entry.version) == normalized) return entry;
    }
    return null;
  }

  static String normalizeVersion(String version) {
    String trimmed = version.trim();
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      trimmed = trimmed.substring(1);
    }
    return trimmed.split('+').first.trim();
  }

  static bool shouldShowWhatsNew({
    required String? lastSeenVersion,
    String installedVersion = currentVersion,
    List<ReleaseNotes> releases = all,
  }) {
    final ReleaseNotes? release = forVersion(
      installedVersion,
      releases: releases,
    );
    if (release == null || release.highlights.isEmpty) return false;
    if (lastSeenVersion == null || lastSeenVersion.trim().isEmpty) {
      return true;
    }
    return normalizeVersion(lastSeenVersion) !=
        normalizeVersion(installedVersion);
  }
}
