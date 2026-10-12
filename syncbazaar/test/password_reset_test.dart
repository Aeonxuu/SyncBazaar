import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';

/// The self-service "forgot password" flow: request a code by email, then
/// use it to set a new password. The only path back into an account for
/// anyone above the person who created it — there is no admin above an
/// owner to reset it for them.
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

  group('requesting a reset', () {
    test('reports no failure whether or not the email has an account', () async {
      final repository = repositoryReplying({
        'detail': 'If the email is registered, a reset code has been sent.',
      });

      expect(
        await repository.requestPasswordReset(email: 'nobody@example.com'),
        isNull,
      );
    });

    test('sends only the lowercased email', () async {
      Map<String, dynamic>? sent;
      final repository = repositoryReplying(
        {'detail': 'ok'},
        onRequest: (request) =>
            sent = jsonDecode(request.body) as Map<String, dynamic>,
      );

      await repository.requestPasswordReset(email: '  A@B.com ');

      expect(sent!['email'], 'a@b.com');
    });

    test('a real connectivity failure is reported, not swallowed', () async {
      final repository = AuthRepository(
        apiClient: ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
      );

      final failure = await repository.requestPasswordReset(
        email: 'a@b.com',
      );

      expect(failure, isNotNull);
      expect(failure!.toLowerCase(), contains('connection'));
    });
  });

  group('confirming a reset', () {
    test('a correct code reports no failure', () async {
      final repository = repositoryReplying({
        'detail': 'Password reset successful.',
      });

      expect(
        await repository.confirmPasswordReset(
          email: 'a@b.com',
          code: '123456',
          newPassword: 'correcthorse',
        ),
        isNull,
      );
    });

    test('sends the code and the new password twice, matching the confirm serializer', () async {
      Map<String, dynamic>? sent;
      final repository = repositoryReplying(
        {'detail': 'ok'},
        onRequest: (request) =>
            sent = jsonDecode(request.body) as Map<String, dynamic>,
      );

      await repository.confirmPasswordReset(
        email: '  A@B.com ',
        code: ' 123456 ',
        newPassword: 'correcthorse',
      );

      expect(sent!['email'], 'a@b.com');
      expect(sent!['code'], '123456');
      expect(sent!['new_password'], 'correcthorse');
      expect(sent!['new_password_confirm'], 'correcthorse');
    });

    test('a wrong code returns the server wording', () async {
      final repository = repositoryReplying(
        {'error': 'Invalid email or code.'},
        status: 400,
      );

      expect(
        await repository.confirmPasswordReset(
          email: 'a@b.com',
          code: '000000',
          newPassword: 'correcthorse',
        ),
        contains('Invalid email or code'),
      );
    });

    test('an expired code says so, distinctly from a wrong one', () async {
      // Unlike verify-account, the server keeps these two messages distinct
      // for a reset — the client just needs to pass through whichever one
      // it gets.
      final repository = repositoryReplying(
        {'error': 'Reset code expired. Please request a new one.'},
        status: 400,
      );

      final failure = await repository.confirmPasswordReset(
        email: 'a@b.com',
        code: '123456',
        newPassword: 'correcthorse',
      );

      expect(failure, contains('expired'));
      expect(failure, isNot(contains('Invalid')));
    });
  });
}
