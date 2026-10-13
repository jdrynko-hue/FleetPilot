/// Detect failed auth callbacks without exposing provider descriptions or tokens.
bool hasAuthRedirectError(Uri uri) {
  bool hasError(Map<String, String> params) =>
      (params['error'] ?? '').trim().isNotEmpty ||
      (params['error_code'] ?? '').trim().isNotEmpty;
  if (hasError(uri.queryParameters)) return true;
  try {
    return hasError(Uri.splitQueryString(uri.fragment));
  } on FormatException {
    return false;
  }
}
