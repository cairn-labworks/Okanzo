/// A selectable overall appearance for the app.
///
/// [midnight] is retained for legacy dark-mode preferences. The other styles
/// support light, dark and system appearances.
enum AppTheme {
  classic('CLASSIC', 'Original', 'Sage, adapts to light and dark'),
  midnight('MIDNIGHT', 'Midnight', 'Deep green and sage, always dark'),
  sculpted('SCULPTED', 'Sculpted', 'Satin surfaces and tactile controls'),
  liquidGlass(
    'LIQUID_GLASS',
    'Liquid Glass',
    'Frosted layers and curved light',
  );

  const AppTheme(this.storageName, this.displayName, this.description);

  final String storageName;
  final String displayName;
  final String description;

  static AppTheme fromName(String? name) {
    for (final AppTheme theme in values) {
      if (theme.storageName == name) return theme;
    }
    return AppTheme.classic;
  }
}
