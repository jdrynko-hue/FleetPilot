import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'localization.dart';

/// Standard Flutter controls use the same language as Flotaryx's own copy.
final supportedMaterialLocales = supportedLanguages
    .map((code) => Locale(code)).toList(growable: false);
const materialLocalizationDelegates = GlobalMaterialLocalizations.delegates;

Locale materialLocale(String language) =>
    Locale(supportedLanguages.contains(language) ? language : 'en');
