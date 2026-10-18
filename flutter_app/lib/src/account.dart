// Accounts: sign up / in / out, password recovery, and syncing the Store to
// the user's encrypted vault. The data key lives only on the device (and,
// wrapped, in the vault); see crypto.dart for the scheme.
//
// Sync is "local first": every change is saved on the device at once and
// pushed ~1s later. Writes carry the vault version; if another device saved
// in between, its copy wins and the user is told.

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'crypto.dart' as crypto;
import 'models.dart';
import 'seed.dart';
import 'store.dart';

enum AccountStatus {
  /// No account on this device: show the sign-in screen.
  signedOut,

  /// Using the app without an account (data only on this device).
  guest,

  /// First sign-in: show the recovery key, then create the vault.
  setup,

  /// Signed in, data decrypted.
  unlocked,

  /// Opened a password-reset email link: ask for recovery key + new password.
  recovering,
}

enum SyncState { idle, syncing, offline }

const minPasswordLength = 10;

class AccountController extends ChangeNotifier {
  AccountController({
    required this.store,
    required this.backend,
    required SharedPreferences? prefs,
    this.iterations = crypto.kdfIterations,
  }) : _prefs = prefs;

  final Store store;

  /// Null when accounts are not available (then the app runs in guest mode).
  final Backend? backend;
  final SharedPreferences? _prefs;
  final int iterations;

  static const _kMode = 'account_mode', _kKey = 'account_key', _kVersion = 'account_version', _kDirty = 'account_dirty';

  AccountStatus status = AccountStatus.signedOut;
  SyncState sync = SyncState.idle;

  /// Shown once on the setup screen; the user must store it.
  String? recoveryKey;
  String? _notice;

  crypto.PasswordKeys? _pendingKeys;
  SecretKey? _dataKey;
  int _version = 0;
  bool _dirty = false, _applying = false, _busy = false, _again = false;
  Timer? _debounce;
  StreamSubscription<BackendEvent>? _sub;

  bool get available => backend != null;
  String? get email => backend?.email;

  /// True when this device was used without an account before (offer to keep that data).
  bool get wasGuest => _prefs?.getString(_kMode) == 'guest';

  /// A one-off message for the user (e.g. a sync conflict). Reading clears it.
  String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  Future<void> init() async {
    store.addListener(_onStoreChanged);
    _sub = backend?.events.listen(_onEvent);
    final key = _prefs?.getString(_kKey);
    final b = backend;
    if (b != null && key != null && b.hasSession) {
      _dataKey = SecretKey(base64.decode(key));
      _version = _prefs?.getInt(_kVersion) ?? 0;
      _dirty = _prefs?.getBool(_kDirty) ?? false;
      status = AccountStatus.unlocked;
      unawaited(pull());
    } else if (key != null) {
      // session gone (signed out elsewhere / expired): don't keep account data around
      await _wipe();
      status = AccountStatus.signedOut;
    } else {
      status = b == null || wasGuest ? AccountStatus.guest : AccountStatus.signedOut;
    }
    notifyListeners();
  }

  void _onEvent(BackendEvent e) {
    switch (e) {
      case BackendEvent.passwordRecovery:
        status = AccountStatus.recovering;
        notifyListeners();
      case BackendEvent.signedOut:
        if (status == AccountStatus.unlocked || status == AccountStatus.setup) {
          unawaited(_wipe().then((_) {
            status = AccountStatus.signedOut;
            notifyListeners();
          }));
        }
    }
  }

  Backend _need() => backend ?? (throw const BackendError('Contas indisponíveis nesta versão.'));

  // ---------------- sign up / in ----------------

  /// Returns false when the user must confirm their email before signing in.
  Future<bool> signUp(String email, String password) async {
    _checkPassword(password);
    final keys = await crypto.derivePasswordKeys(email, password, iterations: iterations);
    final ready = await _need().signUp(email.trim(), keys.authSecret);
    if (ready) await _openVault(keys);
    return ready;
  }

  Future<void> signIn(String email, String password) async {
    final keys = await crypto.derivePasswordKeys(email, password, iterations: iterations);
    await _need().signIn(email.trim(), keys.authSecret);
    await _openVault(keys);
  }

  Future<void> sendPasswordReset(String email) => _need().sendPasswordReset(email.trim());

  void continueAsGuest() {
    _prefs?.setString(_kMode, 'guest');
    status = AccountStatus.guest;
    notifyListeners();
  }

  /// From guest mode: show the sign-in screen (the device data stays until an account opens).
  void showSignIn() {
    status = AccountStatus.signedOut;
    notifyListeners();
  }

  Future<void> _openVault(crypto.PasswordKeys keys) async {
    final v = await _need().fetchVault();
    if (v == null) {
      _pendingKeys = keys;
      recoveryKey = crypto.newRecoveryKey();
      status = AccountStatus.setup;
      notifyListeners();
      return;
    }
    final SecretKey dk;
    try {
      dk = await crypto.unwrapKey(keys.wrappingKey, v.wrappedKeyPassword);
    } catch (_) {
      throw const BackendError('Não foi possível desbloquear os dados desta conta.');
    }
    await _unlock(dk, v);
  }

  /// Creates the vault after the user has stored their recovery key.
  Future<void> finishSetup({required bool keepDeviceData}) async {
    final keys = _pendingKeys!, rk = recoveryKey!;
    final dk = await crypto.newDataKey();
    final state = keepDeviceData ? store.state : emptyState();
    final row = VaultRow(
      iterations: iterations,
      wrappedKeyPassword: await crypto.wrapKey(keys.wrappingKey, dk),
      wrappedKeyRecovery: await crypto.wrapKey(await crypto.recoveryWrappingKey(rk), dk),
      ciphertext: await crypto.encryptJson(dk, state.toJson()),
      version: 1,
    );
    await _need().createVault(row);
    _pendingKeys = null;
    recoveryKey = null;
    await _unlock(dk, row);
  }

  Future<void> _unlock(SecretKey dk, VaultRow v) async {
    final state = AppState.fromJson(await crypto.decryptJson(dk, v.ciphertext));
    _dataKey = dk;
    _version = v.version;
    _dirty = false;
    await _prefs?.setString(_kMode, 'account');
    await _prefs?.setString(_kKey, base64.encode(await dk.extractBytes()));
    await _persistSync();
    _apply(state);
    status = AccountStatus.unlocked;
    sync = SyncState.idle;
    notifyListeners();
  }

  // ---------------- recovery ----------------

  /// After opening the reset link: unlock with the recovery key and set a new password.
  Future<void> completeRecovery(String recoveryKey, String newPassword) async {
    _checkPassword(newPassword);
    final b = _need();
    final email = b.email;
    if (email == null) throw const BackendError('A ligação expirou. Pede outro email de recuperação.');
    final keys = await crypto.derivePasswordKeys(email, newPassword, iterations: iterations);

    var v = await b.fetchVault();
    if (v == null) {
      // never finished setting up: nothing encrypted yet, just set the password
      await b.setAuthSecret(keys.authSecret);
      return _openVault(keys);
    }
    final SecretKey dk;
    try {
      dk = await crypto.unwrapKey(await crypto.recoveryWrappingKey(recoveryKey), v.wrappedKeyRecovery);
    } on FormatException catch (e) {
      throw BackendError(e.message);
    } catch (_) {
      throw const BackendError('Chave de recuperação errada.');
    }
    await b.setAuthSecret(keys.authSecret);
    final wrapped = await crypto.wrapKey(keys.wrappingKey, dk);
    while (!await b.updateVault(expectedVersion: v!.version, wrappedKeyPassword: wrapped)) {
      v = await b.fetchVault(); // another device saved meanwhile; retry on the fresh version
    }
    await _unlock(dk, (await b.fetchVault())!);
  }

  Future<void> cancelRecovery() => signOut();

  // ---------------- sign out / delete ----------------

  Future<void> signOut() async {
    if (_dirty) await push(); // best effort: don't lose the last change
    await backend?.signOut();
    await _wipe();
    status = AccountStatus.signedOut;
    notifyListeners();
  }

  /// Deletes the account and its vault on the server, then this device's copy.
  Future<void> deleteAccount() async {
    await _need().deleteAccount();
    await _wipe();
    status = AccountStatus.signedOut;
    notifyListeners();
  }

  Future<void> _wipe() async {
    _debounce?.cancel();
    _dataKey = null;
    _version = 0;
    _dirty = false;
    _pendingKeys = null;
    recoveryKey = null;
    await _prefs?.remove(_kKey);
    await _prefs?.remove(_kVersion);
    await _prefs?.remove(_kDirty);
    await _prefs?.remove(_kMode);
    _apply(emptyState());
  }

  // ---------------- sync ----------------

  void _apply(AppState s) {
    _applying = true;
    try {
      store.replaceState(s);
    } finally {
      _applying = false;
    }
  }

  void _onStoreChanged() {
    if (_applying || status != AccountStatus.unlocked) return;
    _dirty = true;
    _prefs?.setBool(_kDirty, true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => unawaited(push()));
  }

  Future<void> _persistSync() async {
    await _prefs?.setInt(_kVersion, _version);
    await _prefs?.setBool(_kDirty, _dirty);
  }

  void _setSync(SyncState s) {
    sync = s;
    notifyListeners();
  }

  /// Upload local changes. Safe to call any time.
  Future<void> push() async {
    if (status != AccountStatus.unlocked || !_dirty || _dataKey == null) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    _setSync(SyncState.syncing);
    try {
      final ok = await backend!.updateVault(
          expectedVersion: _version, ciphertext: await crypto.encryptJson(_dataKey!, store.state.toJson()));
      if (ok) {
        _version++;
        _dirty = false;
        await _persistSync();
      } else {
        await _pullRemote();
      }
      _setSync(SyncState.idle);
    } catch (_) {
      _setSync(SyncState.offline);
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        unawaited(push());
      }
    }
  }

  /// Fetch changes made on other devices (on start and when the app resumes).
  Future<void> pull() async {
    if (status != AccountStatus.unlocked || _busy) return;
    _busy = true;
    _setSync(SyncState.syncing);
    try {
      await _pullRemote();
      _setSync(SyncState.idle);
    } catch (_) {
      _setSync(SyncState.offline);
    } finally {
      _busy = false;
    }
    if (_dirty) await push();
  }

  Future<void> _pullRemote() async {
    final v = await backend!.fetchVault();
    if (v == null || v.version == _version || _dataKey == null) return;
    final state = AppState.fromJson(await crypto.decryptJson(_dataKey!, v.ciphertext));
    if (_dirty) _notice = 'Os dados foram alterados noutro dispositivo. A tua última alteração aqui não foi guardada.';
    _version = v.version;
    _dirty = false;
    await _persistSync();
    _apply(state);
  }

  void _checkPassword(String p) {
    if (p.length < minPasswordLength) {
      throw const BackendError('A palavra-passe precisa de pelo menos $minPasswordLength caracteres.');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}

class AccountScope extends InheritedNotifier<AccountController> {
  const AccountScope({super.key, required AccountController account, required super.child})
      : super(notifier: account);

  static AccountController of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AccountScope>()
        : context.getInheritedWidgetOfExactType<AccountScope>();
    return scope!.notifier!;
  }
}
