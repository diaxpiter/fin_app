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
import 'merge.dart';
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

enum Notice { syncConflict }

const minPasswordLength = 12;

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
  static const _kOnboarding = 'account_onboarding', _kOnboarded = 'account_onboarded';
  static const _kBase = 'account_base', _kRescue = 'account_rescue', _kEmail = 'account_email';
  static const _kSessionOnly = 'account_session_only';

  AccountStatus status = AccountStatus.signedOut;
  SyncState sync = SyncState.idle;

  /// Shown once on the setup screen; the user must store it.
  String? recoveryKey;
  Notice? _notice;

  crypto.PasswordKeys? _pendingKeys;
  SecretKey? _dataKey;
  int _version = 0;
  bool _dirty = false, _applying = false, _busy = false, _again = false;

  /// The last copy both this device and the server agreed on: the base for merging after a conflict.
  AppState? _base;

  /// Counts local edits, so one made while a push is in flight is not mistaken for synced.
  int _rev = 0, _conflicts = 0;

  /// False on a shared device: the key and data are not kept on it, and signing in is needed after a reload.
  bool rememberDevice = true;
  Timer? _debounce;
  StreamSubscription<BackendEvent>? _sub;

  bool get available => backend != null;
  String? get email => backend?.email;

  /// True when this device was used without an account before (offer to keep that data).
  bool get wasGuest => _prefs?.getString(_kMode) == 'guest';

  /// A brand-new account, or a guest on a device with nothing in it, still has to go through the first-run setup.
  bool get needsOnboarding =>
      (status == AccountStatus.unlocked || status == AccountStatus.guest) && (_prefs?.getBool(_kOnboarding) ?? false);

  /// Arms the setup once for an empty guest; a latch, so it stays open while the user fills the plan in.
  void _armGuestSetup() {
    final p = _prefs;
    if (p == null || (p.getBool(_kOnboarded) ?? false) || p.containsKey(_kOnboarding)) return;
    if (store.state.recurring.isEmpty && store.state.movements.isEmpty) p.setBool(_kOnboarding, true);
  }

  Future<void> finishOnboarding() async {
    await _prefs?.remove(_kOnboarding);
    await _prefs?.setBool(_kOnboarded, true);
    notifyListeners();
  }

  /// A one-off message for the user (e.g. a sync conflict). Reading clears it.
  Notice? takeNotice() {
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
      _base = _readBase();
      status = AccountStatus.unlocked;
      unawaited(pull());
    } else if (key != null) {
      // session gone (signed out elsewhere / expired): don't keep account data around,
      // except edits that never reached the server: they are merged in at the next sign-in
      final rescue = _rescue();
      await _wipe();
      if (rescue != null) await _prefs?.setString(_kRescue, rescue);
      status = AccountStatus.signedOut;
    } else if (b != null && b.hasSession && (_prefs?.getBool(_kSessionOnly) ?? false)) {
      // shared-device session: nothing was kept, so the login has to be repeated
      await b.signOut();
      await _wipe();
      status = AccountStatus.signedOut;
    } else {
      status = b == null || wasGuest ? AccountStatus.guest : AccountStatus.signedOut;
      if (status == AccountStatus.guest) _armGuestSetup();
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
          final rescue = _rescue();
          unawaited(_wipe().then((_) async {
            if (rescue != null) await _prefs?.setString(_kRescue, rescue);
            status = AccountStatus.signedOut;
            notifyListeners();
          }));
        }
    }
  }

  Backend _need() => backend ?? (throw const BackendError(ErrorCode.unavailable));

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
    _armGuestSetup();
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
      throw const BackendError(ErrorCode.unlockFailed);
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
    await _prefs?.setBool(_kOnboarding, true);
    await _unlock(dk, row);
  }

  Future<void> _unlock(SecretKey dk, VaultRow v) async {
    var state = AppState.fromJson(await crypto.decryptJson(dk, v.ciphertext));
    _dataKey = dk;
    _version = v.version;
    _dirty = false;
    _base = _copy(state);
    final email = backend?.email?.toLowerCase();
    await _prefs?.setString(_kMode, 'account');
    await _prefs?.setString(_kEmail, email ?? '');
    if (rememberDevice) {
      await _prefs?.setString(_kKey, base64.encode(await dk.extractBytes()));
      await _prefs?.remove(_kSessionOnly);
    } else {
      await _prefs?.remove(_kKey);
      await _prefs?.setBool(_kSessionOnly, true);
    }
    store.persist = rememberDevice;
    // edits from an earlier session that never reached the server: merge them back in
    final rescued = _takeRescue(email);
    if (rescued != null) {
      state = mergeStates(emptyState(), rescued, state);
      _dirty = true;
    }
    await _persistSync();
    _persistBase();
    _apply(state);
    status = AccountStatus.unlocked;
    sync = SyncState.idle;
    store.ensureRecurring(); // roll the bills forward to this month (syncs if anything was added)
    notifyListeners();
    if (_dirty) unawaited(push());
  }

  /// The store edits its state in place, so the merge base has to be a separate copy.
  static AppState _copy(AppState s) => AppState.fromJson(s.toJson());

  AppState? _readBase() {
    try {
      final raw = _prefs?.getString(_kBase);
      return raw == null ? null : AppState.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  void _persistBase() {
    if (!rememberDevice || _base == null) return;
    _prefs?.setString(_kBase, jsonEncode(_base!.toJson()));
  }

  /// Unsynced edits as JSON, for [_kRescue]; null when there is nothing to save or the device is shared.
  String? _rescue() {
    if (!_dirty || !rememberDevice) return null;
    return jsonEncode({'email': _prefs?.getString(_kEmail) ?? '', 'state': store.state.toJson()});
  }

  AppState? _takeRescue(String? email) {
    final raw = _prefs?.getString(_kRescue);
    if (raw == null) return null;
    _prefs?.remove(_kRescue);
    try {
      final j = jsonDecode(raw) as Map;
      return j['email'] == email ? AppState.fromJson(j['state']) : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------- recovery ----------------

  /// After opening the reset link: unlock with the recovery key and set a new password.
  Future<void> completeRecovery(String recoveryKey, String newPassword) async {
    _checkPassword(newPassword);
    final b = _need();
    final email = b.email;
    if (email == null) throw const BackendError(ErrorCode.linkExpired);
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
    } on FormatException {
      throw const BackendError(ErrorCode.invalidRecoveryKey);
    } catch (_) {
      throw const BackendError(ErrorCode.wrongRecoveryKey);
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

  /// Returns false, and signs out of nothing, when changes on this device haven't reached the
  /// server (offline): ask the user, then call again with [force].
  Future<bool> signOut({bool force = false}) async {
    if (_dirty) {
      await push();
      if (_dirty && !force) return false;
    }
    _dirty = false;
    await backend?.signOut();
    await _wipe();
    status = AccountStatus.signedOut;
    notifyListeners();
    return true;
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
    await _prefs?.remove(_kOnboarding);
    await _prefs?.remove(_kOnboarded);
    await _prefs?.remove(_kBase);
    await _prefs?.remove(_kRescue);
    await _prefs?.remove(_kEmail);
    await _prefs?.remove(_kSessionOnly);
    _base = null;
    store.persist = true;
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
    _rev++;
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
      final rev = _rev, snapshot = store.state.toJson();
      final ok = await backend!
          .updateVault(expectedVersion: _version, ciphertext: await crypto.encryptJson(_dataKey!, snapshot));
      if (ok) {
        _version++;
        _conflicts = 0;
        _dirty = _rev != rev; // edited while uploading: still unsynced
        _base = AppState.fromJson(snapshot);
        await _persistSync();
        _persistBase();
        if (_dirty) _again = true;
      } else {
        await _pullRemote(); // merges the other device's changes with ours
        if (++_conflicts <= 3) _again = true; // and uploads the result (bounded: a bad server can't spin this)
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
    if (v.version < _version) return; // older than what this device already holds: a replayed copy, ignore
    final remote = AppState.fromJson(await crypto.decryptJson(_dataKey!, v.ciphertext));
    _version = v.version;
    if (_dirty) {
      _apply(mergeStates(_base ?? emptyState(), store.state, remote));
      _notice = Notice.syncConflict;
    } else {
      _apply(remote);
    }
    _base = _copy(remote);
    await _persistSync();
    _persistBase();
  }

  void _checkPassword(String p) {
    if (p.length < minPasswordLength) {
      throw const BackendError(ErrorCode.shortPassword, min: minPasswordLength);
    }
    // everything rests on this password if the database ever leaks: refuse the obvious ones
    final lower = p.toLowerCase();
    if (p.split('').toSet().length < 5 || (p.length < 16 && _common.any(lower.contains))) {
      throw const BackendError(ErrorCode.weakPassword);
    }
  }

  static const _common = ['password', 'passw0rd', '123456', 'qwerty', 'abcdef', 'letmein', 'iloveyou', 'welcome', 'palavrapasse'];

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
