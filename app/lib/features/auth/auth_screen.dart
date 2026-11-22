import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../core/state.dart';
import '../../core/tokens.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/ui.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _register = false, _busy = false;
  final _name = TextEditingController(), _email = TextEditingController(), _pass = TextEditingController();

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final a = ref.read(authProvider.notifier);
      if (_register) {
        await a.register(_name.text.trim(), _email.text.trim(), _pass.text);
      } else {
        await a.login(_email.text.trim(), _pass.text);
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demo() async {
    _email.text = 'demo@bythepeople.app';
    _pass.text = 'demo1234';
    setState(() => _register = false);
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PageBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 24),
              const Center(child: BrandMark(size: 124)),
              const SizedBox(height: 18),
              Center(child: Text('By the People', style: display(26, w: 620))),
              const SizedBox(height: 6),
              Center(child: Text('Report problems. Rally neighbours.', style: ui(14, color: C.inkSoft))),
              const SizedBox(height: 28),
              FrostedPanel(
                padding: const EdgeInsets.all(18),
                child: Column(children: [
                  SegmentedToggle(labels: const ['Sign in', 'Join as Scout'], index: _register ? 1 : 0, onChanged: (i) => setState(() => _register = i == 1)),
                  const SizedBox(height: 16),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: _register ? _Field(controller: _name, hint: 'Full name', icon: Icons.person_outline) : const SizedBox(width: double.infinity),
                  ),
                  if (_register) const SizedBox(height: 12),
                  _Field(controller: _email, hint: 'Email', icon: Icons.mail_outline, type: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _Field(controller: _pass, hint: 'Password', icon: Icons.lock_outline, obscure: true, onSubmit: _submit),
                  const SizedBox(height: 18),
                  PillButton(label: _register ? 'Create account' : 'Sign in', onPressed: _busy ? null : _submit, loading: _busy),
                ]),
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton.icon(
                  onPressed: _busy ? null : _demo,
                  icon: const Icon(Icons.bolt_rounded, color: C.ember),
                  label: Text('Try the demo account', style: ui(14, w: 700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? type;
  final VoidCallback? onSubmit;
  const _Field({required this.controller, required this.hint, required this.icon, this.obscure = false, this.type, this.onSubmit});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: type,
      autocorrect: false,
      textCapitalization: hint == 'Full name' ? TextCapitalization.words : TextCapitalization.none,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
      style: ui(15, w: 600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: ui(15, color: C.inkSoft),
        prefixIcon: Icon(icon, color: C.inkSoft, size: 20),
        filled: true,
        fillColor: C.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
      ),
    );
  }
}
