import 'dart:async';

import 'package:fin_app/src/backend.dart';

/// In-memory stand-in for Supabase. Shared between "devices" to test sync.
class FakeServer {
  final users = <String, String>{}; // email -> auth secret (what the server stores)
  final vaults = <String, VaultRow>{}; // email -> vault
  final confirmed = <String>{};
  bool requireConfirmation = false;
}

class FakeBackend implements Backend {
  FakeBackend(this.server);
  final FakeServer server;
  String? _user;
  bool offline = false;
  final _events = StreamController<BackendEvent>.broadcast();

  void emit(BackendEvent e) => _events.add(e);

  @override
  bool get hasSession => _user != null;
  @override
  String? get email => _user;
  @override
  Stream<BackendEvent> get events => _events.stream;

  void _net() {
    if (offline) throw const BackendError(ErrorCode.offline);
  }

  @override
  Future<bool> signUp(String email, String authSecret) async {
    _net();
    if (server.users.containsKey(email)) throw const BackendError(ErrorCode.emailExists);
    server.users[email] = authSecret;
    if (server.requireConfirmation) return false;
    server.confirmed.add(email);
    _user = email;
    return true;
  }

  @override
  Future<void> signIn(String email, String authSecret) async {
    _net();
    if (server.users[email] != authSecret) throw const BackendError(ErrorCode.invalidCredentials);
    if (!server.confirmed.contains(email)) throw const BackendError(ErrorCode.emailNotConfirmed);
    _user = email;
  }

  /// Simulates opening the reset link from the email.
  void openResetLink(String email) {
    _user = email;
    emit(BackendEvent.passwordRecovery);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    emit(BackendEvent.signedOut);
  }

  @override
  Future<void> sendPasswordReset(String email) async => _net();

  @override
  Future<void> setAuthSecret(String authSecret) async {
    _net();
    server.users[_user!] = authSecret;
  }

  @override
  Future<VaultRow?> fetchVault() async {
    _net();
    return server.vaults[_user!];
  }

  @override
  Future<void> createVault(VaultRow row) async {
    _net();
    server.vaults[_user!] = row;
  }

  @override
  Future<bool> updateVault({required int expectedVersion, String? ciphertext, String? wrappedKeyPassword}) async {
    _net();
    final v = server.vaults[_user!]!;
    if (v.version != expectedVersion) return false;
    server.vaults[_user!] = VaultRow(
      iterations: v.iterations,
      wrappedKeyPassword: wrappedKeyPassword ?? v.wrappedKeyPassword,
      wrappedKeyRecovery: v.wrappedKeyRecovery,
      ciphertext: ciphertext ?? v.ciphertext,
      version: v.version + 1,
    );
    return true;
  }

  @override
  Future<void> deleteAccount() async {
    _net();
    server.vaults.remove(_user);
    server.users.remove(_user);
    await signOut();
  }
}
