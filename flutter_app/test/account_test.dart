import 'dart:convert';

import 'package:fin_app/src/account.dart';
import 'package:fin_app/src/backend.dart';
import 'package:fin_app/src/crypto.dart' as crypto;
import 'package:fin_app/src/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';

const email = 'ana@example.com';
const password = 'correct horse battery';

/// One "device": its own local storage and store, talking to the shared server.
Future<(AccountController, FakeBackend, Store)> device(FakeServer server, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final store = Store.memory();
  final backend = FakeBackend(server);
  final account = AccountController(store: store, backend: backend, prefs: p, iterations: 1000);
  await account.init();
  return (account, backend, store);
}

Future<AccountController> signedUp(FakeServer server) async {
  final (a, _, _) = await device(server);
  expect(await a.signUp(email, password), isTrue);
  expect(a.status, AccountStatus.setup);
  expect(a.recoveryKey, isNotNull);
  return a;
}

void main() {
  group('crypto', () {
    test('seal/open round-trip; wrong key fails', () async {
      final k = await crypto.newDataKey();
      final sealed = await crypto.encryptJson(k, {'a': 1});
      expect(await crypto.decryptJson(k, sealed), {'a': 1});
      await expectLater(crypto.decryptJson(await crypto.newDataKey(), sealed), throwsA(anything));
    });

    test('password keys are deterministic and the auth secret differs from the key', () async {
      final a = await crypto.derivePasswordKeys('A@x.com ', 'pw', iterations: 1000);
      final b = await crypto.derivePasswordKeys('a@x.com', 'pw', iterations: 1000);
      expect(a.authSecret, b.authSecret);
      expect(a.authSecret, isNot(base64Url.encode(await a.wrappingKey.extractBytes()).replaceAll('=', '')));
      final c = await crypto.derivePasswordKeys('a@x.com', 'pw2', iterations: 1000);
      expect(c.authSecret, isNot(a.authSecret));
    });

    test('recovery key format round-trips and tolerates formatting', () {
      final k = crypto.newRecoveryKey();
      expect(k, matches(RegExp(r'^([A-Z2-7]{4}-){7}[A-Z2-7]{4}$')));
      expect(crypto.parseRecoveryKey(k), hasLength(20));
      expect(crypto.parseRecoveryKey(' ${k.toLowerCase().replaceAll('-', ' ')} '), crypto.parseRecoveryKey(k));
      expect(() => crypto.parseRecoveryKey('ABCD'), throwsFormatException);
    });
  });

  group('accounts', () {
    test('new device without accounts history shows sign-in; guest choice sticks', () async {
      final (a, _, _) = await device(FakeServer());
      expect(a.status, AccountStatus.signedOut);
      a.continueAsGuest();
      expect(a.status, AccountStatus.guest);
      final (b, _, _) = await device(FakeServer(), prefs: {'account_mode': 'guest'});
      expect(b.status, AccountStatus.guest);
    });

    test('sign up → setup → unlocked; the server only holds ciphertext', () async {
      final server = FakeServer();
      final a = await signedUp(server);
      await a.finishSetup(keepDeviceData: true); // Store.memory() holds the example data
      expect(a.status, AccountStatus.unlocked);

      final row = server.vaults[email]!;
      expect(row.ciphertext.contains('Salário'), isFalse);
      expect(utf8.decode(base64.decode(row.ciphertext), allowMalformed: true).contains('Salário'), isFalse);
      expect(server.users[email], isNot(password)); // the real password never reaches the server
    });

    test('a new account starts empty unless the device data is kept', () async {
      final server = FakeServer();
      final a = await signedUp(server);
      await a.finishSetup(keepDeviceData: false);
      expect(a.store.state.movements, isEmpty);
      expect(a.needsOnboarding, isTrue, reason: 'new account asks for fixed bills');
      await a.finishOnboarding();
      expect(a.needsOnboarding, isFalse);
    });

    test('signing in to an existing account skips onboarding', () async {
      final server = FakeServer();
      await (await signedUp(server)).finishSetup(keepDeviceData: false);
      final (b, _, _) = await device(server);
      await b.signIn(email, password);
      expect(b.needsOnboarding, isFalse);
    });

    test('second device signs in and sees the same data; edits sync both ways', () async {
      final server = FakeServer();
      final a = await signedUp(server);
      await a.finishSetup(keepDeviceData: false);
      a.store.addMovement(date: '2026-11-02', description: 'Café', category: 'Alimentação', cents: 150, estado: 'Pago');
      await a.push();

      final (b, _, storeB) = await device(server);
      await b.signIn(email, password);
      expect(b.status, AccountStatus.unlocked);
      expect(storeB.state.movements.single.description, 'Café');

      storeB.addMovement(date: '2026-11-03', description: 'Pão', category: 'Alimentação', cents: 90, estado: 'Pago');
      await b.push();
      await a.pull();
      expect(a.store.state.movements.map((m) => m.description), ['Café', 'Pão']);
    });

    test('wrong password is rejected', () async {
      final server = FakeServer();
      await (await signedUp(server)).finishSetup(keepDeviceData: false);
      final (b, _, _) = await device(server);
      await expectLater(b.signIn(email, 'wrong password!'), throwsA(isA<BackendError>()));
    });

    test('email confirmation: sign up returns false and sign-in waits for it', () async {
      final server = FakeServer()..requireConfirmation = true;
      final (a, _, _) = await device(server);
      expect(await a.signUp(email, password), isFalse);
      expect(a.status, AccountStatus.signedOut);
      await expectLater(a.signIn(email, password), throwsA(isA<BackendError>()));
      server.confirmed.add(email);
      await a.signIn(email, password);
      expect(a.status, AccountStatus.setup);
    });

    test('short passwords are refused before anything is sent', () async {
      final server = FakeServer();
      final (a, _, _) = await device(server);
      await expectLater(a.signUp(email, 'short'), throwsA(isA<BackendError>()));
      expect(server.users, isEmpty);
    });

    test('forgot password: recovery key + new password unlocks the same data', () async {
      final server = FakeServer();
      final a = await signedUp(server);
      final rk = a.recoveryKey!;
      await a.finishSetup(keepDeviceData: false);
      a.store.addMovement(date: '2026-11-02', description: 'Renda', category: 'Moradia', cents: 50000, estado: 'Pago');
      await a.push();

      final (b, backendB, storeB) = await device(server);
      backendB.openResetLink(email);
      await Future<void>.delayed(Duration.zero);
      expect(b.status, AccountStatus.recovering);
      await expectLater(b.completeRecovery(crypto.newRecoveryKey(), 'a brand new pass'), throwsA(isA<BackendError>()));
      await b.completeRecovery(rk, 'a brand new pass');
      expect(b.status, AccountStatus.unlocked);
      expect(storeB.state.movements.single.description, 'Renda');

      // old password no longer works, new one does
      final (c, _, _) = await device(server);
      await expectLater(c.signIn(email, password), throwsA(isA<BackendError>()));
      await c.signIn(email, 'a brand new pass');
      expect(c.status, AccountStatus.unlocked);
    });

    test('conflict: the other device wins and the user is told', () async {
      final server = FakeServer();
      final a = await signedUp(server);
      await a.finishSetup(keepDeviceData: false);
      final (b, _, storeB) = await device(server);
      await b.signIn(email, password);

      a.store.addMovement(date: '2026-11-02', description: 'A', category: 'Outros', cents: 1, estado: 'Pago');
      await a.push();
      storeB.addMovement(date: '2026-11-02', description: 'B', category: 'Outros', cents: 1, estado: 'Pago');
      await b.push();

      expect(storeB.state.movements.single.description, 'A');
      expect(b.takeNotice(), isNotNull);
    });

    test('offline edits are kept and pushed later', () async {
      final server = FakeServer();
      final a = await signedUp(server);
      await a.finishSetup(keepDeviceData: false);
      final backendA = a.backend! as FakeBackend;
      backendA.offline = true;
      a.store.addMovement(date: '2026-11-02', description: 'X', category: 'Outros', cents: 1, estado: 'Pago');
      await a.push();
      expect(a.sync, SyncState.offline);
      backendA.offline = false;
      await a.pull();
      expect(a.sync, SyncState.idle);
      expect(server.vaults[email]!.version, 2);
    });

    test('sign out wipes the device; delete account removes it from the server', () async {
      final server = FakeServer();
      final a = await signedUp(server);
      await a.finishSetup(keepDeviceData: true);
      await a.signOut();
      expect(a.status, AccountStatus.signedOut);
      expect(a.store.state.movements, isEmpty);

      await a.signIn(email, password);
      expect(a.store.state.movements, isNotEmpty);
      await a.deleteAccount();
      expect(server.vaults, isEmpty);
      expect(a.store.state.movements, isEmpty);
    });
  });
}
