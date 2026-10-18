// Login + encrypted vault storage. [SupabaseBackend] talks to Supabase; tests
// use an in-memory fake. Nothing that crosses this boundary is readable: the
// password is replaced by a derived auth secret and the data is ciphertext.
// Database schema and access rules: ../../supabase/schema.sql

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class VaultRow {
  const VaultRow({
    required this.iterations,
    required this.wrappedKeyPassword,
    required this.wrappedKeyRecovery,
    required this.ciphertext,
    required this.version,
  });
  final int iterations, version;
  final String wrappedKeyPassword, wrappedKeyRecovery, ciphertext;
}

enum ErrorCode {
  invalidCredentials, emailNotConfirmed, emailExists, rateLimited, invalidEmail, offline, server,
  unavailable, unlockFailed, linkExpired, wrongRecoveryKey, invalidRecoveryKey, shortPassword, other,
}

/// A failure to show the user; the text comes from S.error (i18n.dart).
class BackendError implements Exception {
  const BackendError(this.code, {this.detail, this.min});
  final ErrorCode code;
  final String? detail;
  final int? min;
  @override
  String toString() => 'BackendError(${code.name}${detail == null ? '' : ': $detail'})';
}

enum BackendEvent { passwordRecovery, signedOut }

abstract class Backend {
  bool get hasSession;
  String? get email;
  Stream<BackendEvent> get events;

  /// Returns true when the account is ready to use, false when the user must
  /// first confirm their email.
  Future<bool> signUp(String email, String authSecret);
  Future<void> signIn(String email, String authSecret);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> setAuthSecret(String authSecret);

  Future<VaultRow?> fetchVault();
  Future<void> createVault(VaultRow row);

  /// Optimistic write: succeeds only if the stored version is [expectedVersion].
  /// Returns false on a conflict (another device saved first).
  Future<bool> updateVault({required int expectedVersion, String? ciphertext, String? wrappedKeyPassword});
  Future<void> deleteAccount();
}

class SupabaseBackend implements Backend {
  SupabaseBackend(this._client, {this.redirectTo}) {
    _client.auth.onAuthStateChange.listen((s) {
      switch (s.event) {
        case sb.AuthChangeEvent.passwordRecovery:
          _events.add(BackendEvent.passwordRecovery);
        case sb.AuthChangeEvent.signedOut:
          _events.add(BackendEvent.signedOut);
        default:
          break;
      }
    }, onError: (_) {});
  }

  final sb.SupabaseClient _client;

  /// Where email links (confirmation, password reset) bring the user back to.
  final String? redirectTo;
  final _events = StreamController<BackendEvent>.broadcast();

  sb.GoTrueClient get _auth => _client.auth;

  @override
  bool get hasSession => _auth.currentSession != null;
  @override
  String? get email => _auth.currentUser?.email;
  @override
  Stream<BackendEvent> get events => _events.stream;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on sb.AuthException catch (e) {
      throw _authError(e);
    } on sb.PostgrestException catch (e) {
      throw BackendError(ErrorCode.server, detail: e.code ?? e.message);
    } on BackendError {
      rethrow;
    } catch (_) {
      throw const BackendError(ErrorCode.offline);
    }
  }

  static BackendError _authError(sb.AuthException e) => switch (e.code) {
        'invalid_credentials' => const BackendError(ErrorCode.invalidCredentials),
        'email_not_confirmed' => const BackendError(ErrorCode.emailNotConfirmed),
        'user_already_exists' || 'email_exists' => const BackendError(ErrorCode.emailExists),
        'over_email_send_rate_limit' || 'over_request_rate_limit' => const BackendError(ErrorCode.rateLimited),
        'email_address_invalid' || 'validation_failed' => const BackendError(ErrorCode.invalidEmail),
        _ => BackendError(ErrorCode.other, detail: e.message),
      };

  @override
  Future<bool> signUp(String email, String authSecret) => _guard(() async {
        final r = await _auth.signUp(email: email, password: authSecret, emailRedirectTo: redirectTo);
        // With email enumeration protection on, an existing email returns a user with no identities.
        if (r.user != null && (r.user!.identities?.isEmpty ?? false)) {
          throw const BackendError(ErrorCode.emailExists);
        }
        return r.session != null;
      });

  @override
  Future<void> signIn(String email, String authSecret) =>
      _guard(() => _auth.signInWithPassword(email: email, password: authSecret));

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {/* offline: the local session is cleared anyway */}
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.resetPasswordForEmail(email, redirectTo: redirectTo));

  @override
  Future<void> setAuthSecret(String authSecret) =>
      _guard(() => _auth.updateUser(sb.UserAttributes(password: authSecret)));

  String get _uid => _auth.currentUser!.id;

  @override
  Future<VaultRow?> fetchVault() => _guard(() async {
        final row = await _client.from('vaults').select().eq('user_id', _uid).maybeSingle();
        if (row == null) return null;
        return VaultRow(
          iterations: ((row['kdf'] as Map)['iterations'] as num).toInt(),
          wrappedKeyPassword: row['wrapped_key_password'] as String,
          wrappedKeyRecovery: row['wrapped_key_recovery'] as String,
          ciphertext: row['ciphertext'] as String,
          version: (row['version'] as num).toInt(),
        );
      });

  @override
  Future<void> createVault(VaultRow r) => _guard(() => _client.from('vaults').insert({
        'user_id': _uid,
        'kdf': {'alg': 'pbkdf2-sha256', 'iterations': r.iterations},
        'wrapped_key_password': r.wrappedKeyPassword,
        'wrapped_key_recovery': r.wrappedKeyRecovery,
        'ciphertext': r.ciphertext,
        'version': r.version,
      }));

  @override
  Future<bool> updateVault({required int expectedVersion, String? ciphertext, String? wrappedKeyPassword}) =>
      _guard(() async {
        final rows = await _client
            .from('vaults')
            .update({
              if (ciphertext != null) 'ciphertext': ciphertext,
              if (wrappedKeyPassword != null) 'wrapped_key_password': wrappedKeyPassword,
              'version': expectedVersion + 1,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', _uid)
            .eq('version', expectedVersion)
            .select('version');
        return rows.isNotEmpty;
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _client.rpc('delete_account');
        await signOut();
      });
}
