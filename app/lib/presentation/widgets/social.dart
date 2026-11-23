import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

String authorityStatusLabel(String s) => const {
      'open': 'Awaiting response',
      'acknowledged': 'Acknowledged',
      'in_progress': 'In progress',
      'resolved': 'Resolved',
    }[s] ?? s;

Color authorityStatusColor(String s) => const {
      'open': Color(0xFFEDEDEA),
      'acknowledged': Color(0xFFE3EFF9),
      'in_progress': Color(0xFFEAE6F6),
      'resolved': Color(0xFFE0F1E6),
    }[s] ?? C.muted;

/// Heart button with an optimistic count. Calls [onToggle] with the new state; reverts when it throws.
class LikeButton extends StatefulWidget {
  final bool liked;
  final int count;
  final Future<void> Function(bool next) onToggle;
  final Color color;
  final bool compact;
  const LikeButton({super.key, required this.liked, required this.count, required this.onToggle, this.color = C.ink, this.compact = false});
  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with SingleTickerProviderStateMixin {
  late bool _liked = widget.liked;
  late int _count = widget.count;
  bool _busy = false;
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void didUpdateWidget(LikeButton old) {
    super.didUpdateWidget(old);
    if (!_busy) {
      _liked = widget.liked;
      _count = widget.count;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (_busy) return;
    final next = !_liked;
    setState(() {
      _busy = true;
      _liked = next;
      _count += next ? 1 : -1;
    });
    if (next) _pop.forward(from: 0);
    try {
      await widget.onToggle(next);
    } catch (e) {
      if (mounted) {
        setState(() {
          _liked = !next;
          _count += next ? -1 : 1;
        });
        toastError(context, e, fallback: 'Could not update your like. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 60),
    ]).animate(_pop);
    return TapScale(
      onTap: _tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: scale,
            child: Icon(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 22, color: _liked ? C.ember : widget.color),
          ),
          const SizedBox(width: 5),
          Text('$_count', style: ui(13, color: widget.color, w: 600)),
        ]),
      ),
    );
  }
}

/// Icon + count used for comments and shares.
class CountAction extends StatelessWidget {
  final IconData icon;
  final int? count;
  final VoidCallback? onTap;
  final Color color;
  final String? label;
  const CountAction({super.key, required this.icon, this.count, this.onTap, this.color = C.ink, this.label});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: color),
            if (count != null) ...[const SizedBox(width: 5), Text('$count', style: ui(13, color: color, w: 600))],
            if (label != null) ...[const SizedBox(width: 5), Text(label!, style: ui(13, color: color, w: 600))],
          ]),
        ),
      );
}

/// Small pill: "@RMC_Raipur · Acknowledged".
class AuthorityChip extends StatelessWidget {
  final Issue issue;
  final Color fg;
  const AuthorityChip(this.issue, {super.key, this.fg = C.ink});
  @override
  Widget build(BuildContext context) {
    final a = issue.authority;
    if (a == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: authorityStatusColor(issue.authorityStatus), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.account_balance_outlined, size: 12, color: C.ink),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${a.handle.isNotEmpty ? a.handle : a.name} · ${authorityStatusLabel(issue.authorityStatus)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ui(11.5, color: C.ink, w: 600),
          ),
        ),
      ]),
    );
  }
}

class EscalatedBadge extends StatelessWidget {
  const EscalatedBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: C.ember, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.trending_up_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text('Escalated', style: ui(11.5, color: Colors.white, w: 600)),
        ]),
      );
}

/// Opens the system share sheet (WhatsApp, X, ...) with the server's share text, then records the share.
Future<void> shareIssue(BuildContext context, WidgetRef ref, Issue issue) async {
  final text = issue.shareText ?? '${issue.title}\n${issue.publicUrl ?? ''}'.trim();
  HapticFeedback.selectionClick();
  try {
    final result = await SharePlus.instance.share(ShareParams(text: text, subject: issue.title));
    if (result.status == ShareResultStatus.dismissed) return;
    await ref.read(actionsProvider).recordShare(issue.id);
  } catch (e) {
    if (context.mounted) toastError(context, e, fallback: 'Could not share right now. Try again.');
  }
}

/// Reddit-style upvote: arrow + count in a hairline pill. Filled accent when active.
/// Optimistic: flips instantly, rolls back and shows a friendly toast when [onToggle] throws.
class UpvoteButton extends StatefulWidget {
  final bool active;
  final int count;
  final Future<void> Function(bool next) onToggle;
  final bool large;
  const UpvoteButton({super.key, required this.active, required this.count, required this.onToggle, this.large = false});
  @override
  State<UpvoteButton> createState() => _UpvoteButtonState();
}

class _UpvoteButtonState extends State<UpvoteButton> with SingleTickerProviderStateMixin {
  late bool _on = widget.active;
  late int _count = widget.count;
  bool _busy = false;
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  @override
  void didUpdateWidget(UpvoteButton old) {
    super.didUpdateWidget(old);
    if (!_busy) {
      _on = widget.active;
      _count = widget.count;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (_busy) return;
    final next = !_on;
    setState(() {
      _busy = true;
      _on = next;
      _count = (_count + (next ? 1 : -1)).clamp(0, 1 << 30);
    });
    if (next) _pop.forward(from: 0);
    try {
      await widget.onToggle(next);
    } catch (e) {
      if (mounted) {
        setState(() {
          _on = !next;
          _count = (_count + (next ? -1 : 1)).clamp(0, 1 << 30);
        });
        toastError(context, e, fallback: 'Could not save your upvote. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 60),
    ]).animate(_pop);
    final fg = _on ? C.ember : C.ink;
    return Semantics(
      button: true,
      label: _on ? 'Remove upvote' : 'Upvote',
      child: TapScale(
        onTap: _tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: widget.large ? 40 : 34,
          padding: EdgeInsets.symmetric(horizontal: widget.large ? 14 : 11),
          decoration: BoxDecoration(
            color: _on ? C.ember.withValues(alpha: 0.10) : C.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _on ? C.ember : C.line, width: _on ? 1.2 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(scale: scale, child: Icon(Icons.arrow_upward_rounded, size: widget.large ? 22 : 20, color: fg)),
            const SizedBox(width: 5),
            Text('$_count', style: ui(13.5, color: fg, w: 650)),
          ]),
        ),
      ),
    );
  }
}

/// Compact optimistic "Support" button for feed cards (citizens only; location checked by the action).
class SupportChipButton extends ConsumerStatefulWidget {
  final Issue issue;
  final VoidCallback? onSupported;
  const SupportChipButton({super.key, required this.issue, this.onSupported});
  @override
  ConsumerState<SupportChipButton> createState() => _SupportChipButtonState();
}

class _SupportChipButtonState extends ConsumerState<SupportChipButton> {
  late bool _on = widget.issue.supportedByMe;
  bool _busy = false;

  @override
  void didUpdateWidget(SupportChipButton old) {
    super.didUpdateWidget(old);
    if (!_busy) _on = widget.issue.supportedByMe;
  }

  Future<void> _tap() async {
    if (_on || _busy) return;
    setState(() {
      _busy = true;
      _on = true;
    });
    try {
      final r = await ref.read(actionsProvider).support(widget.issue.id);
      if (mounted) showToast(context, r.converted ? 'This is now an event.' : 'Thanks for backing this.');
      widget.onSupported?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _on = false);
        toastError(context, e, fallback: 'Could not add your support. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TapScale(
        onTap: _on ? null : _tap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _on ? C.muted : C.ink,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_on ? Icons.check_rounded : Icons.thumb_up_alt_outlined, size: 15, color: _on ? C.inkSoft : Colors.white),
            const SizedBox(width: 6),
            Text(_on ? 'Supported' : 'Support', style: ui(13, color: _on ? C.inkSoft : Colors.white, w: 600)),
          ]),
        ),
      );
}
