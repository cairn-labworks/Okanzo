/// App-language overrides; system follows the device's preferred languages.
enum AppLanguage {
  system('system', 'Use device language'),
  english('en', 'English'),
  spanish('es', 'Español'),
  portuguese('pt-BR', 'Português (Brasil)'),
  french('fr', 'Français'),
  german('de', 'Deutsch'),
  japanese('ja', '日本語'),
  korean('ko', '한국어'),
  chinese('zh-Hans', '简体中文'),
  italian('it', 'Italiano'),
  hindi('hi', 'हिन्दी'),
  arabic('ar', 'العربية'),
  indonesian('id', 'Bahasa Indonesia'),
  turkish('tr', 'Türkçe'),
  polish('pl', 'Polski'),
  dutch('nl', 'Nederlands'),
  vietnamese('vi', 'Tiếng Việt'),
  thai('th', 'ไทย'),
  russian('ru', 'Русский'),
  swedish('sv', 'Svenska'),
  danish('da', 'Dansk'),
  norwegian('nb', 'Norsk bokmål');

  const AppLanguage(this.storageName, this.displayName);

  final String storageName;
  final String displayName;

  static AppLanguage fromName(String? name) {
    for (final AppLanguage language in values) {
      if (language.storageName == name) return language;
    }
    return AppLanguage.system;
  }
}
