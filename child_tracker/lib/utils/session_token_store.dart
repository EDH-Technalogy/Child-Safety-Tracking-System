class SessionTokenStore {
  static String? currentToken;

  static bool get hasToken => (currentToken ?? '').isNotEmpty;

  static void clear() {
    currentToken = null;
  }
}
