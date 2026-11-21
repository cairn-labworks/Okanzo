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

  static const String currentVersion = '1.6.1';

  static const List<ReleaseNotes> all = <ReleaseNotes>[
    ReleaseNotes(
      version: '1.6.1',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.theme,
          title: 'Canvas holding entry',
          description: 'Add holdings with searchable pickers, live values and centered save confirmations.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.assets,
          title: 'Valuables your way',
          description: 'Track metals, gems and jewellery using quoted or custom per-gram rates, or a total appraisal.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.security,
          title: 'App lock on every screen',
          description: 'Protect screens and dialogs, and authenticate before changing app lock or exporting protected data.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.portfolio,
          title: 'Hide balances everywhere',
          description: 'Hide amounts and quantities across Home, Statistics and Portfolios while keeping editors usable.',
        ),
      ],
    ),
    ReleaseNotes(
      version: '1.6.0',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.assets,
          title: 'Guided entry forms',
          description: 'Read clearer labels, recognize picker icons and move to the next empty required field.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.exchanges,
          title: 'Custom names and price lookup',
          description: 'Set an optional custom name. Okanzo fetches missing market prices when you save.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.portfolio,
          title: 'Your default portfolio first',
          description: 'Okanzo opens your default portfolio on launch. It switches to the new default when you change it.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.statistics,
          title: 'Compact chart totals',
          description: 'Donut charts show large totals in abbreviated units for each currency.',
        ),
      ],
    ),
    ReleaseNotes(
      version: '1.5.0',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.exchanges,
          title: 'Company and crypto ticker search',
          description: 'Search stocks, funds and cryptocurrencies by name or ticker. You can also enter a ticker manually.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.security,
          title: 'Screenshot protection toggle',
          description: 'Okanzo blocks screenshots and recent-apps previews by default. Change this in Security settings.',
        ),
      ],
    ),
    ReleaseNotes(
      version: '1.4.5',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.theme,
          title: 'Midnight and sage store screenshots',
          description: 'Store screenshots and promotional previews match the home overview and Midnight theme.',
        ),
      ],
    ),
    ReleaseNotes(
      version: '1.4.4',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.theme,
          title: 'Midnight and sage store screenshots',
          description: 'Store screenshots and promotional previews match the home overview and Midnight theme.',
        ),
      ],
    ),
    ReleaseNotes(
      version: '1.4.3',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.security,
          title: 'F-Droid-compatible Android builds',
          description: 'Android packages omit opaque dependency metadata.',
        ),
      ],
    ),
    ReleaseNotes(
      version: '1.4.2',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.theme,
          title: 'Midnight theme and home overview',
          description: 'The home overview has sage accents and a net worth total. Assets and Liabilities have separate tabs.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.assets,
          title: 'Grouped settings and compact forms',
          description: "Settings groups options by category and has one Theme control. Entry forms use less space. App information is separate from What's new.",
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.currency,
          title: 'Simple net worth',
          description:
              'Shorten the home net worth using currency-specific units',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.exchanges,
          title: 'Prices in your chosen currency',
          description: "Okanzo converts market prices into your asset's currency when you fetch or refresh them. Prices also convert when you change the currency.",
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.backup,
          title: 'Price refresh and backup encryption',
          description: 'Okanzo avoids duplicate price lookups. Backup encryption runs off the main thread.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.releaseNotes,
          title: "What's new on update",
          description: 'Okanzo shows release notes after an update. Open them again in Settings.',
        ),
      ],
    ),
    ReleaseNotes(
      version: '1.3.0',
      highlights: <ReleaseHighlight>[
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.language,
          title: '21 app languages',
          description:
              'Choose an app language in Settings or use the device language.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.exchanges,
          title: 'Global stock exchanges',
          description: 'Look up stocks and funds on exchanges in the United States, Europe and Asia. Choose which exchanges appear in your preferred list.',
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.crypto,
          title: 'Crypto tickers and currency conversion',
          description: "Enter a crypto ticker such as BTC or ETH. Okanzo converts the quote into your asset's currency.",
        ),
        ReleaseHighlight(
          icon: ReleaseHighlightIcon.releaseNotes,
          title: "What's new on update",
          description: 'Okanzo shows release notes after an update. Open them again in Settings.',
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
