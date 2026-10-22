// Account screens: sign in / create account / forgot password, the one-time
// recovery key, and setting a new password from a reset link.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account.dart';
import '../app_controller.dart';
import '../backend.dart';
import '../theme.dart';
import '../widgets.dart';
import 'preferences.dart';

/// Centred, width-capped column used by all account screens.
class AuthFrame extends StatelessWidget {
  const AuthFrame({super.key, required this.children, this.maxWidth = 420});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.password = false,
    this.autofill,
    this.keyboard,
    this.onSubmitted,
    this.hint,
  });
  final String label;
  final TextEditingController controller;
  final bool password;
  final Iterable<String>? autofill;
  final TextInputType? keyboard;
  final ValueChanged<String>? onSubmitted;
  final String? hint;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: TextField(
          controller: widget.controller,
          obscureText: widget.password && _hidden,
          autocorrect: false,
          enableSuggestions: !widget.password,
          autofillHints: widget.autofill,
          keyboardType: widget.keyboard,
          textInputAction: widget.onSubmitted == null ? TextInputAction.next : TextInputAction.done,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            filled: true,
            fillColor: Palette.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: _hidden ? AppScope.of(context).s.show : AppScope.of(context).s.hide,
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
      );
}

class _Primary extends StatelessWidget {
  const _Primary({required this.label, required this.busy, required this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: busy ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Palette.accent,
              foregroundColor: Palette.bg,
              disabledBackgroundColor: Palette.surface2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(label),
          ),
        ),
      );
}

Widget _message(String? text, {bool error = true}) => text == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: error ? Palette.neg : Palette.accent)),
      );


// ---------------------------------------------------------------------------

enum _Mode { signIn, signUp, forgot }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.signIn;
  final _email = TextEditingController(), _pass = TextEditingController(), _pass2 = TextEditingController();
  bool _shared = false;
  bool _busy = false;
  String? _error, _info;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  void _switch(_Mode m) => setState(() {
        _mode = m;
        _error = null;
        _info = null;
      });

  Future<void> _submit() async {
    final account = AccountScope.of(context, listen: false);
    final s = AppScope.of(context, listen: false).s;
    final email = _email.text.trim();
    setState(() {
      _error = null;
      _info = null;
    });
    if (!email.contains('@')) return setState(() => _error = s.enterEmail);
    if (_mode == _Mode.signUp && _pass.text != _pass2.text) {
      return setState(() => _error = s.passwordsDontMatch);
    }
    if (_mode != _Mode.forgot && _pass.text.isEmpty) return setState(() => _error = s.enterPassword);
    setState(() => _busy = true);
    account.rememberDevice = !_shared;
    try {
      switch (_mode) {
        case _Mode.signIn:
          await account.signIn(email, _pass.text);
        case _Mode.signUp:
          final ready = await account.signUp(email, _pass.text);
          if (!ready && mounted) {
            _pass2.clear();
            _mode = _Mode.signIn;
            _info = s.confirmEmailSent(email);
          }
        case _Mode.forgot:
          await account.sendPasswordReset(email);
          _info = s.resetEmailSent;
      }
    } on BackendError catch (e) {
      _error = s.error(e);
    } catch (_) {
      _error = s.somethingWrong;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final s = AppScope.of(context).s;
    final (title, action) = switch (_mode) {
      _Mode.signIn => (s.signIn, s.signIn),
      _Mode.signUp => (s.createAccount, s.createAccount),
      _Mode.forgot => (s.recoverAccess, s.sendEmail),
    };
    return AuthFrame(children: [
      Row(children: [Expanded(child: Lbl(s.appName)), const LanguageSwitch()]),
      const SizedBox(height: 4),
      H1(title),
      const SizedBox(height: 10),
      Text(s.privacyBlurb, style: const TextStyle(fontSize: 14, height: 1.45, color: Palette.muted)),
      const SizedBox(height: 8),
      _Field(
        label: s.email,
        controller: _email,
        keyboard: TextInputType.emailAddress,
        autofill: const [AutofillHints.email, AutofillHints.username],
        onSubmitted: _mode == _Mode.forgot ? (_) => _submit() : null,
      ),
      if (_mode != _Mode.forgot)
        _Field(
          label: s.password,
          controller: _pass,
          password: true,
          hint: _mode == _Mode.signUp ? s.atLeastChars(minPasswordLength) : null,
          autofill: [_mode == _Mode.signUp ? AutofillHints.newPassword : AutofillHints.password],
          onSubmitted: _mode == _Mode.signIn ? (_) => _submit() : null,
        ),
      if (_mode == _Mode.signUp)
        _Field(
          label: s.repeatPassword,
          controller: _pass2,
          password: true,
          autofill: const [AutofillHints.newPassword],
          onSubmitted: (_) => _submit(),
        ),
      _message(_error),
      _message(_info, error: false),
      if (_mode != _Mode.forgot)
        CheckboxListTile(
          value: _shared,
          onChanged: _busy ? null : (v) => setState(() => _shared = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(s.sharedDevice, style: const TextStyle(fontSize: 14)),
          subtitle: Text(s.sharedDeviceHint, style: const TextStyle(fontSize: 12, color: Palette.muted)),
        ),
      _Primary(label: action, busy: _busy, onPressed: _submit),
      if (_busy && _mode != _Mode.forgot)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(s.securingKey,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Palette.muted)),
        ),
      const SizedBox(height: 18),
      if (_mode == _Mode.signIn) ...[
        TextButton(onPressed: () => _switch(_Mode.signUp), child: Text(s.noAccountYet)),
        TextButton(
          onPressed: () => _switch(_Mode.forgot),
          style: TextButton.styleFrom(foregroundColor: Palette.muted),
          child: Text(s.forgotPassword),
        ),
      ] else
        TextButton(onPressed: () => _switch(_Mode.signIn), child: Text(s.haveAccount)),
      const SizedBox(height: 8),
      const Divider(color: Palette.line),
      TextButton(
        onPressed: _busy ? null : account.continueAsGuest,
        style: TextButton.styleFrom(foregroundColor: Palette.muted),
        child: Text(s.continueAsGuest),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _saved = false, _busy = false;
  bool? _keep;
  String? _error;

  Future<void> _finish(AccountController account) async {
    final s = AppScope.of(context, listen: false).s;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await account.finishSetup(keepDeviceData: _keep ?? false);
    } on BackendError catch (e) {
      _error = s.error(e);
    } catch (_) {
      _error = s.somethingWrong;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final s = AppScope.of(context).s;
    final key = account.recoveryKey ?? '';
    _keep ??= account.wasGuest;
    return AuthFrame(children: [
      Lbl(s.lastStep),
      const SizedBox(height: 12),
      H1(s.recoveryKeyTitle, size: 26),
      const SizedBox(height: 12),
      Text(s.recoveryKeyIntro, style: const TextStyle(fontSize: 14, height: 1.45, color: Palette.muted)),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.line2),
        ),
        child: Column(children: [
          SelectableText(key, textAlign: TextAlign.center, style: mono(size: 17, weight: FontWeight.w500).copyWith(height: 1.6)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: key));
              if (context.mounted) toast(context, s.keyCopied);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(s.copy),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        value: _saved,
        onChanged: (v) => setState(() => _saved = v ?? false),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(s.savedKey, style: const TextStyle(fontSize: 15)),
      ),
      CheckboxListTile(
        value: _keep,
        onChanged: (v) => setState(() => _keep = v ?? false),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(s.keepDeviceData, style: const TextStyle(fontSize: 15)),
        subtitle: Text(s.keepDeviceDataSub, style: const TextStyle(fontSize: 12, color: Palette.muted)),
      ),
      _message(_error),
      _Primary(label: s.continueAction, busy: _busy, onPressed: _saved ? () => _finish(account) : null),
    ]);
  }
}

// ---------------------------------------------------------------------------

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _key = TextEditingController(), _pass = TextEditingController(), _pass2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final account = AccountScope.of(context, listen: false);
    final s = AppScope.of(context, listen: false).s;
    if (_pass.text != _pass2.text) return setState(() => _error = s.passwordsDontMatch);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await account.completeRecovery(_key.text, _pass.text);
    } on BackendError catch (e) {
      _error = s.error(e);
    } catch (_) {
      _error = s.somethingWrong;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final s = AppScope.of(context).s;
    return AuthFrame(children: [
      Lbl(account.email ?? s.recoverAccess),
      const SizedBox(height: 12),
      H1(s.newPassword, size: 26),
      const SizedBox(height: 10),
      Text(s.recoveryIntro, style: const TextStyle(fontSize: 14, height: 1.45, color: Palette.muted)),
      _Field(label: s.recoveryKey, controller: _key, hint: 'XXXX-XXXX-XXXX-…'),
      _Field(
        label: s.newPassword,
        controller: _pass,
        password: true,
        hint: s.atLeastChars(minPasswordLength),
        autofill: const [AutofillHints.newPassword],
      ),
      _Field(
        label: s.repeatPassword,
        controller: _pass2,
        password: true,
        autofill: const [AutofillHints.newPassword],
        onSubmitted: (_) => _submit(),
      ),
      _message(_error),
      _Primary(label: s.saveAndSignIn, busy: _busy, onPressed: _submit),
      const SizedBox(height: 12),
      TextButton(
        onPressed: _busy ? null : account.cancelRecovery,
        style: TextButton.styleFrom(foregroundColor: Palette.muted),
        child: Text(s.cancel),
      ),
    ]);
  }
}
