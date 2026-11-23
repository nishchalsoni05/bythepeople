import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/brand_mark.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// One way into the app. Each portal maps to a role on the server.
class Portal {
  final String role, title, blurb, demoEmail, demoPass;
  final IconData icon;
  final Color color;
  final bool canRegister;
  const Portal(this.role, this.title, this.blurb, this.icon, this.color, this.demoEmail, this.demoPass, {this.canRegister = false});
}

const portals = <Portal>[
  Portal('citizen', 'Citizen', 'Report issues, join drives, give surplus', Icons.groups_rounded, C.lime, 'demo@bythepeople.app', 'demo1234', canRegister: true),
  Portal('admin', 'Admin', 'Authority officers: handle the issue queue', Icons.account_balance_rounded, C.sky, 'admin@bythepeople.app', 'admin1234'),
  Portal('neta', 'Neta', 'Elected leaders: your locality at a glance', Icons.how_to_vote_rounded, C.amber, 'neta@bythepeople.app', 'neta1234'),
  Portal('foundation', 'Foundation', 'NGOs: claim and distribute donations', Icons.volunteer_activism_rounded, C.lavender, 'seva@bythepeople.app', 'seva1234', canRegister: true),
];

Portal portalFor(String role) => portals.firstWhere((p) => p.role == role, orElse: () => portals.first);

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  Portal? _portal; // null = chooser
  bool _register = false, _busy = false;
  String? _wrongPortal; // role the server says this account really has
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _pass = TextEditingController(),
      _org = TextEditingController(),
      _regNo = TextEditingController(),
      _about = TextEditingController(),
      _city = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _email, _pass, _org, _regNo, _about, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  void _choose(Portal? p) => setState(() {
        _portal = p;
        _register = false;
        _wrongPortal = null;
      });

  bool get _isFoundation => _portal?.role == 'foundation';

  bool get _valid {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) return false;
    if (!_register) return true;
    if (_name.text.trim().length < 2 || _pass.text.length < 6) return false;
    if (_isFoundation && (_org.text.trim().isEmpty || _regNo.text.trim().isEmpty)) return false;
    return true;
  }

  Future<void> _submit() async {
    final portal = _portal;
    if (portal == null || _busy || !_valid) return;
    setState(() {
      _busy = true;
      _wrongPortal = null;
    });
    try {
      final a = ref.read(authProvider.notifier);
      if (_register) {
        await a.register({
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'password': _pass.text,
          'role': portal.role,
          if (_isFoundation) ...{
            'orgName': _org.text.trim(),
            'regNo': _regNo.text.trim(),
            if (_about.text.trim().isNotEmpty) 'about': _about.text.trim(),
            if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
          },
        });
      } else {
        await a.login(_email.text.trim(), _pass.text, role: portal.role);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'WRONG_PORTAL') {
        final m = RegExp(r'a (\w+) account').firstMatch(e.message);
        setState(() => _wrongPortal = m?.group(1)?.toLowerCase());
        if (m == null) showToast(context, e.message, error: true);
      } else {
        showToast(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemo() {
    final p = _portal!;
    setState(() {
      _register = false;
      _wrongPortal = null;
      _email.text = p.demoEmail;
      _pass.text = p.demoPass;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PageBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: _portal == null ? 16 : 0),
              Center(child: BrandMark(size: _portal == null ? 108 : 72)),
              const SizedBox(height: 12),
              Center(child: Text('By the People', style: display(26, w: 620))),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _portal == null ? 'Civic action, community good, one app.' : 'Continue as ${_portal!.title}',
                  textAlign: TextAlign.center,
                  style: ui(14, color: C.inkSoft),
                ),
              ),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a), child: child),
                ),
                child: _portal == null ? _chooser() : _form(_portal!),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- portal chooser ----
  Widget _chooser() => Column(key: const ValueKey('chooser'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 12), child: Text('Choose your portal', style: ui(17, w: 750))),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 154,
          children: [for (final p in portals) _PortalTile(portal: p, onTap: () => _choose(p))],
        ),
        const SizedBox(height: 16),
        Center(child: Text('Admin and Neta accounts are issued by the platform.', textAlign: TextAlign.center, style: ui(12.5, color: C.inkSoft))),
      ]);

  // ---- login / register ----
  Widget _form(Portal p) {
    return Column(key: ValueKey('form-${p.role}'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : () => _choose(null),
          icon: const Icon(Icons.arrow_back_rounded, size: 18, color: C.ink),
          label: Text('All portals', style: ui(13.5, w: 700)),
        ),
      ),
      FrostedPanel(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
              child: Icon(p.icon, color: C.ink, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p.title} portal', style: ui(16.5, w: 750)),
                Text(p.blurb, style: ui(12.5, color: C.inkSoft, h: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          if (p.canRegister) ...[
            SegmentedToggle(
              labels: const ['Sign in', 'Create account'],
              index: _register ? 1 : 0,
              onChanged: (i) => setState(() {
                _register = i == 1;
                _wrongPortal = null;
              }),
            ),
            const SizedBox(height: 14),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(children: [
              if (_register) ...[
                _Field(controller: _name, hint: _isFoundation ? 'Your name (contact person)' : 'Full name', icon: Icons.person_outline, caps: true, onChanged: _rebuild),
                const SizedBox(height: 12),
              ],
              if (_register && _isFoundation) ...[
                _Field(controller: _org, hint: 'Organisation name', icon: Icons.apartment_rounded, caps: true, onChanged: _rebuild),
                const SizedBox(height: 12),
                _Field(controller: _regNo, hint: 'Registration number', icon: Icons.badge_outlined, onChanged: _rebuild),
                const SizedBox(height: 12),
                _Field(controller: _city, hint: 'City (optional)', icon: Icons.location_city_rounded, caps: true),
                const SizedBox(height: 12),
                _Field(controller: _about, hint: 'What does your organisation do? (optional)', icon: Icons.notes_rounded, caps: true, lines: 2),
                const SizedBox(height: 12),
              ],
            ]),
          ),
          _Field(controller: _email, hint: 'Email', icon: Icons.mail_outline, type: TextInputType.emailAddress, onChanged: _rebuild),
          const SizedBox(height: 12),
          _Field(controller: _pass, hint: _register ? 'Password (6+ characters)' : 'Password', icon: Icons.lock_outline, obscure: true, onSubmit: _submit, onChanged: _rebuild),
          if (_register && _isFoundation) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF0D8), borderRadius: BorderRadius.circular(18)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.verified_user_outlined, size: 18, color: C.ember),
                const SizedBox(width: 8),
                Expanded(child: Text('An admin verifies your registration before you can claim donations.', style: ui(12.5, color: C.inkSoft, h: 1.4))),
              ]),
            ),
          ],
          if (_wrongPortal != null) ...[
            const SizedBox(height: 12),
            _WrongPortal(
              role: _wrongPortal!,
              onSwitch: () {
                final target = portals.where((e) => e.role == _wrongPortal);
                if (target.isNotEmpty) _choose(target.first);
              },
            ),
          ],
          const SizedBox(height: 18),
          PillButton(
            label: _register ? (_isFoundation ? 'Register foundation' : 'Create account') : 'Sign in',
            onPressed: _busy || !_valid ? null : _submit,
            loading: _busy,
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: _busy ? null : _fillDemo,
          icon: const Icon(Icons.bolt_rounded, color: C.ember),
          label: Text('Fill demo ${p.title.toLowerCase()} login', style: ui(14, w: 700)),
        ),
      ),
    ]);
  }

  void _rebuild([String? _]) => setState(() {});
}

class _PortalTile extends StatelessWidget {
  final Portal portal;
  final VoidCallback onTap;
  const _PortalTile({required this.portal, required this.onTap});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: portal.color, borderRadius: BorderRadius.circular(R.card)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38, height: 38,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(portal.icon, size: 20, color: C.ink),
            ),
            const Spacer(),
            Text(portal.title, style: ui(16, w: 750)),
            const SizedBox(height: 2),
            Text(portal.blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(11.5, color: C.ink.withValues(alpha: 0.7), h: 1.25)),
          ]),
        ),
      );
}

class _WrongPortal extends StatelessWidget {
  final String role;
  final VoidCallback onSwitch;
  const _WrongPortal({required this.role, required this.onSwitch});
  @override
  Widget build(BuildContext context) {
    final p = portalFor(role);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFE6D5), borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.swap_horiz_rounded, color: C.ember),
        const SizedBox(width: 10),
        Expanded(child: Text('This is a ${p.title} account. Use the ${p.title} portal.', style: ui(13, w: 650, h: 1.35))),
        const SizedBox(width: 8),
        TextButton(onPressed: onSwitch, child: Text('Switch', style: ui(13.5, color: C.ember, w: 750))),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure, caps;
  final int lines;
  final TextInputType? type;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;
  const _Field({
    required this.controller, required this.hint, required this.icon, this.obscure = false, this.type, this.onSubmit,
    this.onChanged, this.caps = false, this.lines = 1,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: lines > 1 ? TextInputType.multiline : type,
      autocorrect: false,
      minLines: lines,
      maxLines: lines,
      onChanged: onChanged,
      textCapitalization: caps ? TextCapitalization.words : TextCapitalization.none,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
      style: ui(15, w: 600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: ui(15, color: C.inkSoft),
        prefixIcon: Icon(icon, color: C.inkSoft, size: 20),
        filled: true,
        fillColor: C.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(lines > 1 ? 24 : 30), borderSide: BorderSide.none),
      ),
    );
  }
}
