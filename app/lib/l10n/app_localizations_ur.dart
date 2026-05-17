// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Urdu (`ur`).
class AppLocalizationsUr extends AppLocalizations {
  AppLocalizationsUr([String locale = 'ur']) : super(locale);

  @override
  String get appTitle => 'آگ کا پتہ لگانے والا AI';

  @override
  String get detect => 'آگ کا پتہ لگائیں';

  @override
  String get history => 'تاریخ';

  @override
  String get fireDetected => 'آگ کا پتہ چلا!';

  @override
  String get noFire => 'کوئی آگ نہیں';

  @override
  String get confidence => 'اعتماد';

  @override
  String get severity => 'شدت';

  @override
  String get high => 'زیادہ';

  @override
  String get medium => 'درمیانی';

  @override
  String get low => 'کم';
}
