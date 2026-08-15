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
  ///
  /// Applies only once the server is known to be awake — see
  /// [coldStartTimeout].
  static const Duration timeout = Duration(seconds: 10);

  /// The allowance for the first call after a quiet spell.
  ///
  /// The hosted backend runs on a free tier that sleeps after about fifteen
  /// minutes idle. [timeout] alone would fail every first login of the day and
  /// report it as no signal — the one diagnosis guaranteed to send someone
  /// looking at the wifi instead of at the server.
  ///
  /// Sized from measurement rather than the host's advertised figure: two
  /// wakes timed 22s and 39s, so the spread matters more than the average and
  /// this leaves room above the slower one. Erring long costs a spinner on one
  /// call; erring short costs a login that cannot be told from an outage.
  ///
  /// Only the waking call pays this. Once anything answers, [timeout] takes
  /// over and a genuinely dead connection still fails fast.
  static const Duration coldStartTimeout = Duration(seconds: 75);

  /// How long a reply proves the server is still awake.
  ///
  /// Deliberately shorter than the host's own idle-shutdown, so the window
  /// closes before the server actually sleeps rather than after.
  static const Duration warmFor = Duration(minutes: 10);
}
