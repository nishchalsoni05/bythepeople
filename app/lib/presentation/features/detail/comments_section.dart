import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/media.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Small coloured label for admin / neta / foundation authors.
class RoleTag extends StatelessWidget {
  final String role;
  const RoleTag(this.role, {super.key});
  @override
  Widget build(BuildContext context) {
    final (label, bg) = switch (role) {
      'admin' => ('Verifier', Color(0xFFE3EFF9)),
      'neta' => ('Neta', Color(0xFFFCEBD9)),
      'foundation' => ('Foundation', Color(0xFFEAE6F6)),
      _ => ('', C.muted),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: ui(10.5, w: 650)),
    );
  }
}

/// Comments thread with a composer, live-synced through [commentsProvider].
class CommentsSection extends ConsumerStatefulWidget {
  final int issueId;
  const CommentsSection({super.key, required this.issueId});
  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  final _text = TextEditingController();
  final _media = MediaAttachController(max: 2, allowVideo: false);
  final _focus = FocusNode();
  final _key = GlobalKey();
  final List<String> _pending = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Keep the composer visible above the keyboard when it gets focus.
    _focus.addListener(() {
      if (_focus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 320), () {
          final c = _key.currentContext;
          if (mounted && c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 200), alignment: 0.6);
        });
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    _media.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _busy) return;
    final hadMedia = _media.items.isNotEmpty;
    setState(() {
      _busy = true;
      _pending.add(body);
    });
    _text.clear();
    final a = ref.read(actionsProvider);
    try {
      final urls = !hadMedia ? <String>[] : await _media.upload(a.uploadMedia);
      await a.comment(widget.issueId, body, media: urls);
      _media.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) {
        // Roll back: put the text back so nothing is lost.
        if (_text.text.isEmpty) _text.text = body;
        toastError(context, e, fallback: 'Could not post your comment. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pending.remove(body);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(commentsProvider(widget.issueId));
    final me = ref.watch(authProvider).user;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Comments', style: ui(15, w: 650)),
        const SizedBox(width: 8),
        if (async.asData != null) Text('${async.asData!.value.length}', style: ui(13.5, color: C.inkSoft, w: 700)),
      ]),
      const SizedBox(height: 12),
      async.when(
        skipLoadingOnReload: true,
        loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Skeleton(child: Column(children: [SkeletonBox(height: 38), SizedBox(height: 10), SkeletonBox(height: 38)]))),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(commentsProvider(widget.issueId))),
        data: (items) => items.isEmpty && _pending.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  const Icon(Icons.mode_comment_outlined, size: 18, color: C.inkSoft),
                  const SizedBox(width: 8),
                  Expanded(child: Text('No comments yet. Be the first to share a thought.', style: ui(13.5, color: C.inkSoft))),
                ]),
              )
            : Column(children: [
                for (final c in items) _CommentRow(c, mine: c.author.id == me?.id),
                for (final b in _pending)
                  Opacity(
                    opacity: 0.55,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Avatar(me?.asPerson ?? Person(0, '?', 200), size: 32),
                        const SizedBox(width: 10),
                        Expanded(child: Text(b, style: ui(14, h: 1.4))),
                      ]),
                    ),
                  ),
              ]),
      ),
      const SizedBox(height: 4),
      MediaAttachStrip(controller: _media, addLabel: 'Photo'),
      const SizedBox(height: 8),
      Row(key: _key, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 1,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: ui(14.5, w: 500),
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: 'Add a comment',
              hintStyle: ui(14.5, color: C.inkSoft),
              counterText: '',
              filled: true,
              fillColor: C.muted,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TapScale(
          onTap: _text.text.trim().isEmpty ? null : _send,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42, height: 42,
            decoration: BoxDecoration(color: _text.text.trim().isEmpty ? C.inkSoft.withValues(alpha: 0.35) : C.ember, shape: BoxShape.circle),
            child: _busy
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
          ),
        ),
      ]),
    ]);
  }
}

class _CommentRow extends StatelessWidget {
  final IssueComment c;
  final bool mine;
  const _CommentRow(this.c, {required this.mine});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(c.author, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(mine ? 'You' : c.author.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(13.5, w: 650))),
                RoleTag(c.author.role),
                Text('  ·  ${relative(c.createdAt)}', style: ui(11.5, color: C.inkSoft)),
              ]),
              const SizedBox(height: 2),
              Text(c.body, style: ui(14, h: 1.4)),
              if (c.media.isNotEmpty) ...[
                const SizedBox(height: 8),
                MediaGallery(media: c.media, height: 150, radius: 16),
              ],
            ]),
          ),
        ]),
      );
}
