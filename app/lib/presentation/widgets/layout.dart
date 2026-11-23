import 'package:flutter/material.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Caps content width on tablets and large screens so lists stay readable.
/// On phones (which are narrower than [max]) it changes nothing.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.max = 560});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}

/// A full-screen page opened on top of the shell (Leaders, My activity, ...): backdrop plus a back button.
class PushedPage extends StatelessWidget {
  const PushedPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      body: PageBackdrop(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 0),
            child: Row(children: [
              CircleBtn(icon: Icons.arrow_back_rounded, size: 42, onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 14),
              Text(title, style: ui(17, color: C.inkSoft, w: 700)),
            ]),
          ),
          Expanded(
            child: MediaQuery.removePadding(context: context, removeTop: true, child: ContentWidth(child: child)),
          ),
        ]),
      ),
    );
  }
}
