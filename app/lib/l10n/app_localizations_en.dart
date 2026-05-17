// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Fire Detection AI';

  @override
  String get detect => 'Detect Fire';

  @override
  String get history => 'History';

  @override
  String get fireDetected => 'Fire Detected!';

  @override
  String get noFire => 'No Fire';

  @override
  String get confidence => 'Confidence';

  @override
  String get severity => 'Severity';

  @override
  String get high => 'High';

  @override
  String get medium => 'Medium';

  @override
  String get low => 'Low';
}
