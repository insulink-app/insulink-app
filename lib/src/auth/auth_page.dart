import 'package:flutter/material.dart';
import 'package:insulink/src/auth/auth_mode_switch.dart';
import 'package:insulink/src/auth/auth_service.dart';
import 'package:insulink/src/auth/brand_mark.dart';
import 'package:insulink/src/base/labeled_field.dart';
import 'package:insulink/src/base/page_primary_button.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/base/button_loader.dart';

/// Combined sign-in / sign-up screen. Toggles between the two modes; on success
/// the tokens are stored by [AuthService] and [onAuthenticated] advances the
/// gate into the app.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _service = AuthService();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final name = _name.text.trim();
    final password = _password.text;
    final error = _signUp
        ? await _service.signUp(context, name, password)
        : await _service.signIn(context, name, password);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error == null) {
      widget.onAuthenticated();
      return;
    }
    _error(error);
  }

  void _error(String key) {
    Alert(type: AlertType.error, description: key).show(context);
  }

  /// Logo, title and subtitle centred above the fields and the button, all in
  /// the middle of the screen; the switch to the other mode at the foot.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: Center(child: _form())),
                    AuthModeSwitch(
                      signUp: _signUp,
                      onPressed: _busy
                          ? null
                          : () => setState(() => _signUp = !_signUp),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const BrandMark(size: 64),
        const SizedBox(height: 26),
        LocaleText(
          'auth.title',
          textAlign: TextAlign.center,
          style: InkText.bigValue.copyWith(fontSize: 34),
        ),
        const SizedBox(height: 10),
        LocaleText(
          _signUp ? 'auth.subtitle_signup' : 'auth.subtitle_signin',
          textAlign: TextAlign.center,
          style: InkText.body.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: context.ink.muted,
          ),
        ),
        const SizedBox(height: 32),
        _nameField(),
        const SizedBox(height: 18),
        _passwordField(),
        const SizedBox(height: 22),
        _submitButton(),
      ],
    );
  }

  Widget _nameField() {
    return LabeledField(
      labelKey: 'auth.name',
      child: TextField(
        controller: _name,
        enabled: !_busy,
        decoration: InputDecoration(
          hintText: Locales.string(context, 'auth.name_hint'),
        ),
      ),
    );
  }

  Widget _passwordField() {
    return LabeledField(
      labelKey: 'auth.password',
      child: TextField(
        controller: _password,
        obscureText: !_showPassword,
        enabled: !_busy,
        decoration: InputDecoration(
          hintText: Locales.string(context, 'auth.password'),
          suffixIcon: IconButton(
            icon: Icon(
              _showPassword
                  ? PhosphorIconsBold.eyeSlash
                  : PhosphorIconsBold.eye,
              color: context.ink.muted,
            ),
            tooltip: Locales.string(context, 'auth.show_password'),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
    );
  }

  Widget _submitButton() {
    return PagePrimaryButton(
      onPressed: _busy ? null : _submit,
      child: _busy
          ? const ButtonLoader(size: 22)
          : LocaleText(_signUp ? 'auth.signup' : 'auth.signin'),
    );
  }
}
