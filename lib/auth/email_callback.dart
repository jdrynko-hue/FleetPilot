/// Trusted build configuration only; never accepts a URL from browser input.
/// Portal is navigation intent, never an authorization claim.
String authEmailCallback({required String backendUrl,
    required String configuredQaCallback, String? portal}) {
  const qaBackend = 'https://fyestmquqvkdebxxbcky.supabase.co';
  var base = Uri.parse('https://flotaryx.com/app/');
  if (backendUrl == qaBackend) {
    final candidate = Uri.tryParse(configuredQaCallback);
    if (candidate == null || candidate.scheme != 'https' ||
        candidate.host.isEmpty || candidate.userInfo.isNotEmpty ||
        candidate.port != 443 || candidate.path != '/app/' ||
        candidate.hasQuery || candidate.hasFragment ||
        candidate.host == 'flotaryx.com' || candidate.host == 'www.flotaryx.com') {
      throw StateError('QA email return URL is not configured.');
    }
    base = candidate;
  }
  // Production keeps its existing callback; QA can preserve a selected panel.
  if (backendUrl == qaBackend && const {'fleet', 'garage', 'customer', 'search'}.contains(portal)) {
    return base.replace(queryParameters: {'portal': portal!}).toString();
  }
  return base.toString();
}
