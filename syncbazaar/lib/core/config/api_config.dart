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

  /// Whether this build talks to the backend instead of the mock dataset.
  ///
  /// Off by default, so an ordinary `flutter run` still boots the seeded demo
  /// data with no server involved. Turn it on with
  /// `--dart-define=USE_BACKEND=true`.
  ///
  /// The two are exclusive on purpose. Debug builds are also the only ones
  /// allowed to speak plain http (see the debug AndroidManifest), so the build
  /// used for testing against a laptop is exactly the build that seeds mock
  /// data — and a screen showing twelve server products beside twelve seeded
  /// ones is worse than either alone.
  static const bool useBackend = bool.fromEnvironment('USE_BACKEND');

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
