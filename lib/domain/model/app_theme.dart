/// A selectable overall appearance for the app.
///
/// [classic] adapts the shared precision styling to light/dark and wallpaper
/// colours. [midnight] keeps deep-green surfaces, sage accents and tonal depth.
enum AppTheme {
  classic('CLASSIC', 'Classic', 'Sage, adapts to light and dark'),
  midnight('MIDNIGHT', 'Midnight', 'Deep green and sage, always dark');

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
