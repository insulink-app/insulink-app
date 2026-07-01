import 'package:flutter/material.dart';
import 'package:insulink/src/auth/auth_service.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LocaleText(
                  'auth.title',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                LocaleText(
                  _signUp ? 'auth.subtitle_signup' : 'auth.subtitle_signin',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                ),
                const SizedBox(height: 32),
                _field(_name, 'auth.name', false),
                const SizedBox(height: 14),
                _passwordField(),
                const SizedBox(height: 24),
                _submitButton(),
                const SizedBox(height: 12),
                _toggleButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String labelKey, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: Locales.string(context, labelKey),
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _password,
      obscureText: !_showPassword,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: Locales.string(context, 'auth.password'),
        suffixIcon: IconButton(
          icon: Icon(
            _showPassword ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
      ),
    );
  }

  Widget _submitButton() {
    return FilledButton(
      onPressed: _busy ? null : _submit,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      child: _busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : LocaleText(_signUp ? 'auth.signup' : 'auth.signin'),
    );
  }

  Widget _toggleButton() {
    return TextButton(
      onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
      child: LocaleText(_signUp ? 'auth.to_signin' : 'auth.to_signup'),
    );
  }
}
