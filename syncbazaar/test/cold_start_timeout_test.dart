import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/config/api_config.dart';
import 'package:syncbazaar/data/remote/api_client.dart';

/// The hosted backend sleeps when idle and takes about twenty seconds to wake.
///
/// A flat ten-second timeout failed every first call of the day and reported
/// it as no connection — which sends someone to check the wifi while the real
/// answer is that the server is still getting up. These cover the rule that
/// replaced it: wait long only while it is unknown whether the host is awake.
void main() {
  test('the first call of a session gets the cold-start allowance', () {
    final client = ApiClient(baseUrl: 'http://example.test');

    // Nothing has answered yet, so the server may well be asleep.
    expect(client.nextTimeout, ApiConfig.coldStartTimeout);
  });

  test('once something answers, calls fail fast again', () {
    final client = ApiClient(baseUrl: 'http://example.test')..markAwake();

    // This is the bazaar case: a cashier must learn there is no signal
    // within seconds, not wait three quarters of a minute for it.
    expect(client.nextTimeout, ApiConfig.timeout);
  });

  test('after a quiet spell the allowance comes back', () {
    final client = ApiClient(baseUrl: 'http://example.test')
      ..markAwake(DateTime.now().subtract(ApiConfig.warmFor * 2));

    expect(client.nextTimeout, ApiConfig.coldStartTimeout);
  });

  test('a reply just inside the window still counts as awake', () {
    final client = ApiClient(baseUrl: 'http://example.test')
      ..markAwake(
        DateTime.now().subtract(ApiConfig.warmFor - const Duration(minutes: 1)),
      );

    expect(client.nextTimeout, ApiConfig.timeout);
  });

  test('the warm window closes before a free tier would sleep', () {
    // The host sleeps at about fifteen minutes idle. Trusting a reply for
    // longer than that would send a short timeout at a sleeping server.
    expect(ApiConfig.warmFor, lessThan(const Duration(minutes: 15)));
  });

  test('the cold allowance clears the measured wake time', () {
    // Two wakes on the free tier timed 22s and 39s. The allowance has to
    // clear the slower one with room, not merely beat the average -- a wake
    // that overruns is indistinguishable from an outage to whoever is
    // holding the tablet.
    expect(
      ApiConfig.coldStartTimeout,
      greaterThan(const Duration(seconds: 50)),
    );
  });
}
