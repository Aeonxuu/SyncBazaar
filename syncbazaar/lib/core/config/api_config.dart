/// Where the backend lives.
///
/// The one place a host is written down. Everything else builds paths onto
/// [baseUrl], so pointing the app at a different server is a launch flag rather
/// than an edit:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.106:8000
/// ```
///
/// Which host to use depends on where the app is running, because "this
/// machine" means something different to each target:
///
/// | Target                | Host                                  |
/// | --------------------- | ------------------------------------- |
/// | macOS / web / desktop | `http://127.0.0.1:8000`               |
/// | Android emulator      | `http://10.0.2.2:8000`                |
/// | Physical tablet       | this Mac's LAN IP, e.g. `192.168.1.x` |
///
/// The tablet cases need the Django dev server started as
/// `python manage.py runserver 0.0.0.0:8000` — its default binds to localhost
/// only and refuses connections from the network.
class ApiConfig {
  const ApiConfig._();

  /// Defaults to the desktop/web host, since that is where this app is
  /// developed day to day. Compile-time rather than runtime so no build ships
  /// pointing at a laptop by accident.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// How long to wait before deciding the server is unreachable.
  ///
  /// Short on purpose: at a bazaar the answer to "is there signal?" needs to
  /// arrive before the cashier gives up, and every call has an offline path to
  /// fall back to.
  static const Duration timeout = Duration(seconds: 10);
}
