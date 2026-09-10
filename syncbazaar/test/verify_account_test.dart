import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';

/// Confirming a new account with the emailed code.
///
/// Accounts are created unverified and sign-in refuses an unverified account,
/// so before this an employee an owner had just added could not get in at all:
/// the app named the problem and offered nothing to do about it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  AuthRepository repositoryReplying(
    Object body, {
    int status = 200,
    void Function(http.Request request)? onRequest,
  }) => AuthRepository(
    apiClient: ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );

  group('confirming an account', () {
    test('a correct code reports no failure', () async {
      final repository = repositoryReplying({
        'detail': 'Account verified successfully.',
      });

      expect(
        await repository.verifyAccount(email: 'a@b.com', code: '123456'),
        isNull,
      );
    });

    test('sends the email lowercased, with the code', () async {
      Map<String, dynamic>? sent;
      final repository = repositoryReplying(
        {'detail': 'ok'},
        onRequest: (request) =>
            sent = jsonDecode(request.body) as Map<String, dynamic>,
      );

      await repository.verifyAccount(email: '  A@B.com ', code: ' 123456 ');

      expect(sent!['email'], 'a@b.com');
      expect(sent!['code'], '123456');
    });

    test('a wrong code returns the server wording', () async {
      final repository = repositoryReplying(
        {'error': 'Invalid verification code.'},
        status: 400,
      );

      expect(
        await repository.verifyAccount(email: 'a@b.com', code: '000000'),
        contains('Invalid verification code'),
      );
    });

    test('an expired code says so, which is a different fix', () async {
      // Retyping fixes a wrong code. Only a new code fixes an expired one, so
      // collapsing the two into "that did not work" sends someone in circles.
      final repository = repositoryReplying(
        {'detail': 'Verification code expired. Please request a new one.'},
        status: 400,
      );

      final failure = await repository.verifyAccount(
        email: 'a@b.com',
        code: '123456',
      );

      expect(failure, contains('expired'));
      expect(failure, isNot(contains('Invalid')));
    });
  });

  group('asking for a new code', () {
    test('reports no failure when it is sent', () async {
      final repository = repositoryReplying({'detail': 'Sent.'});

      expect(await repository.resendVerification(email: 'a@b.com'), isNull);
    });

    test('carries the failure back rather than pretending', () async {
      final repository = repositoryReplying(
        {'error': 'Account already verified.'},
        status: 400,
      );

      expect(
        await repository.resendVerification(email: 'a@b.com'),
        contains('already verified'),
      );
    });

    test('an unreachable server is reported, not swallowed', () async {
      final repository = AuthRepository(
        apiClient: ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
      );

      final failure = await repository.resendVerification(email: 'a@b.com');

      expect(failure, isNotNull);
      expect(failure!.toLowerCase(), contains('connection'));
    });
  });
}
