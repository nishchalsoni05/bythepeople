import 'package:flutter/material.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/features/donations/create_donation_sheet.dart';
import 'package:by_the_people/presentation/features/gatherings/create_gathering_sheet.dart';
import 'package:by_the_people/presentation/features/report/report_screen.dart';
import 'package:by_the_people/presentation/widgets/sheets.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// The centre "+" of the citizen nav: report an issue, start a gathering, or donate surplus.
Future<void> showCreateSheet(BuildContext context) async {
  final choice = await showAppSheet<int>(
    context,
    title: 'Create',
    subtitle: 'What would you like to do?',
    body: (ctx) => Column(children: [
      _Tile(icon: Icons.campaign_rounded, color: C.amber, title: 'Report an issue', sub: 'Flag a civic problem to your neighbours and the authority', onTap: () => Navigator.pop(ctx, 0)),
      _Tile(icon: Icons.diversity_3_rounded, color: C.lavender, title: 'Start a gathering', sub: 'Plantation, cleanup, blood drive, marathon and more', onTap: () => Navigator.pop(ctx, 1)),
      _Tile(icon: Icons.volunteer_activism_rounded, color: C.lime, title: 'Donate surplus', sub: 'Food, clothes, books: verified foundations collect it', onTap: () => Navigator.pop(ctx, 2)),
    ]),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 0:
      await Navigator.of(context).push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const ReportScreen(),
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ));
    case 1:
      await showCreateGatheringSheet(context);
    case 2:
      await showCreateDonationSheet(context);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.color, required this.title, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: C.ink, size: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: ui(15.5, w: 750)),
                const SizedBox(height: 2),
                Text(sub, style: ui(12.5, color: C.inkSoft, h: 1.3)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: C.inkSoft),
          ]),
        ),
      );
}
