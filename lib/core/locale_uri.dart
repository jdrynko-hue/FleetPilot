Uri withLanguageQuery(Uri uri, String language) => uri.replace(
  queryParameters: {...uri.queryParametersAll, 'lang': [language]},
);
