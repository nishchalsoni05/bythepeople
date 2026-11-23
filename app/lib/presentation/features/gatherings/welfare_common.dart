import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/welfare_di.dart';
import 'package:by_the_people/core/config/env.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/comment.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/widgets/celebrate.dart';
import 'package:by_the_people/presentation/widgets/map.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart' show locationProvider;
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Pieces shared by the gatherings, donations and foundations screens.

/// Absolute URL for a server media path such as `/uploads/ab12.jpg`.
String mediaUrl(String path) {
  if (path.startsWith('http')) return path;
  try {
    return '${Env.apiBaseUrl}$path';
  } catch (_) {
    return path;
  }
}

bool isVideoPath(String p) {
  final s = p.toLowerCase();
  return s.endsWith('.mp4') || s.endsWith('.mov');
}

/// Runs [fn], showing a friendly toast on failure. Returns null when it failed.
Future<T?> guarded<T>(BuildContext context, Future<T> Function() fn) async {
  try {
    return await fn();
  } catch (e) {
    if (context.mounted) toastError(context, e);
  }
  return null;
}

/// Optimistic update: [apply] runs now, [rollback] runs and a toast shows if [run] fails.
Future<V?> optimisticRun<V>(
  BuildContext context, {
  required VoidCallback apply,
  required VoidCallback rollback,
  required Future<V> Function() run,
  String? failMessage,
}) async {
  apply();
  try {
    return await run();
  } catch (e) {
    rollback();
    if (context.mounted) toastError(context, e, fallback: failMessage);
    return null;
  }
}

/// Toasts rewards when there are any.
void cheer(BuildContext context, Rewards? rewards, String headline, {bool confetti = false}) {
  if (!context.mounted) return;
  celebrate(context, rewards: rewards, headline: headline.isEmpty ? null : headline, confetti: confetti);
}

/// Staggered fade-and-rise used when list items appear.
class Enter extends StatefulWidget {
  const Enter({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<Enter> createState() => _EnterState();
}

class _EnterState extends State<Enter> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(Duration(milliseconds: (widget.index.clamp(0, 6)) * 55), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(offset: Offset(0, (1 - t.value) * 18), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Network photo with shimmer while loading and a tidy neutral icon when missing or broken.
class NetPhoto extends StatelessWidget {
  const NetPhoto(this.path, {super.key, this.height = 180, this.radius = 12, this.width, this.fallbackIcon = Icons.image_outlined});
  final String path;
  final double height;
  final double? width;
  final double radius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final w = width ?? double.infinity;
    Widget fallback([IconData? icon]) => Container(
      height: height,
      width: w,
      color: C.muted,
      alignment: Alignment.center,
      child: Icon(icon ?? fallbackIcon, color: C.inkSoft.withValues(alpha: 0.7), size: 28),
    );
    Widget shimmer() => Skeleton(child: Container(height: height, width: w, color: C.line));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: path.isEmpty
          ? fallback()
          : isVideoPath(path)
          ? fallback(Icons.play_circle_outline_rounded)
          : Image.network(
              mediaUrl(path),
              height: height,
              width: w,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback(),
              loadingBuilder: (context, child, progress) => progress == null ? child : shimmer(),
            ),
    );
  }
}

/// Small quiet label with an optional icon. Neutral by default.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.bg = C.muted, this.fg = C.ink});
  final String label;
  final IconData? icon;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12, color: fg, w: 600)),
          ),
        ],
      ),
    );
  }
}

/// Flat white surface with a hairline border.
class WCard extends StatelessWidget {
  const WCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.color = C.surface,
  });
  final Widget child;
  final EdgeInsetsGeometry padding, margin;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
    child: child,
  );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.icon, this.bg = C.surface});
  final int value;
  final String label;
  final IconData? icon;
  final Color bg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RollingNumber(value, style: ui(18, w: 600)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(11.5, color: C.inkSoft, h: 1.2)),
        ],
      ),
    );
  }
}

/// Avatar for a [PersonRef] using the shared gradient style.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.person, {super.key, this.size = 30, this.ring});
  final PersonRef person;
  final double size;
  final Color? ring;
  @override
  Widget build(BuildContext context) => Avatar(Person(person.id, person.label, person.hue), size: size, ring: ring);
}

class PersonLine extends StatelessWidget {
  const PersonLine(this.person, {super.key, this.sub, this.color = C.ink, this.size = 28, this.ring});
  final PersonRef person;
  final String? sub;
  final Color color;
  final double size;
  final Color? ring;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PersonAvatar(person, size: size, ring: ring),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(person.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(13, color: color, w: 600)),
                  ),
                  if (person.role == 'foundation' && person.verified) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified_rounded, size: 14, color: color == Colors.white ? C.lime : const Color(0xFF3B9C6E)),
                  ],
                ],
              ),
              if (sub != null)
                Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(11.5, color: color.withValues(alpha: 0.65))),
            ],
          ),
        ),
      ],
    );
  }
}

class WHeader extends StatelessWidget {
  const WHeader({super.key, required this.title, this.trailing, this.onBack});
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          TopBarAction(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: onBack ?? () => Navigator.of(context).maybePop()),
          const SizedBox(width: 4),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(20, w: 600)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Standard labelled text field.
class WField extends StatelessWidget {
  const WField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.lines = 1,
    this.keyboard,
    this.maxLength,
    this.onChanged,
    this.formatters,
    this.fieldKey,
  });
  final String label;
  final String? hint;
  final TextEditingController controller;
  final int lines;
  final TextInputType? keyboard;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? formatters;
  final Key? fieldKey;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: ui(12.5, color: C.inkSoft, w: 600)),
        ),
        TextField(
          key: fieldKey,
          controller: controller,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          maxLength: maxLength,
          keyboardType: keyboard ?? (lines > 1 ? TextInputType.multiline : TextInputType.text),
          inputFormatters: formatters,
          onChanged: onChanged,
          style: ui(14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: ui(14, color: C.inkSoft.withValues(alpha: 0.6)),
            counterText: '',
            filled: true,
            fillColor: C.muted,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: C.ink, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// Modal bottom sheet with the app's rounded style, keyboard aware and scrollable.
Future<T?> showWelfareSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

/// Scrollable body of a sheet: grabber, title, content.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.title, required this.children, this.subtitle});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 14),
          Text(title, style: ui(18, w: 600)),
          if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: ui(13, color: C.inkSoft, h: 1.4))],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// Photos chosen for a post: uploads each one as soon as it is picked.
class PhotoPicker extends ConsumerStatefulWidget {
  const PhotoPicker({super.key, required this.urls, required this.onChanged, this.max = 3, this.label = 'Add photo'});
  final List<String> urls;
  final ValueChanged<List<String>> onChanged;
  final int max;
  final String label;
  @override
  ConsumerState<PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends ConsumerState<PhotoPicker> {
  bool _busy = false;

  Future<void> _add() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: Text('Take a photo', style: ui(14, w: 500)),
                onTap: () => Navigator.pop(ctx, true),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: Text('Choose from gallery', style: ui(14, w: 500)),
                onTap: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (camera == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final photo = await ref.read(welfarePlatformProvider).pickPhoto(camera: camera);
      if (photo == null) return;
      final url = await ref.read(gatheringActionsProvider).upload(photo);
      if (url.isNotEmpty && mounted) widget.onChanged([...widget.urls, url]);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) showToast(context, 'Could not add that photo.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final u in widget.urls)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: [
                  NetPhoto(u, height: 84, width: 84, radius: 12),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => widget.onChanged(widget.urls.where((e) => e != u).toList()),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: C.ink, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.urls.length < widget.max)
            TapScale(
              onTap: _busy ? null : _add,
              child: Container(
                width: 84,
                decoration: BoxDecoration(
                  color: C.muted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: C.line),
                ),
                child: _busy
                    ? const Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: C.ink)),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_rounded, size: 22, color: C.inkSoft),
                          const SizedBox(height: 4),
                          Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: ui(11, color: C.inkSoft, w: 650),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Like / comment / share row for a post.
class EngagementBar extends StatelessWidget {
  const EngagementBar({
    super.key,
    required this.likes,
    required this.comments,
    required this.shares,
    required this.liked,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    this.trailing,
  });
  final int likes, comments, shares;
  final bool liked;
  final VoidCallback onLike, onComment, onShare;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ActionBtn(icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, count: likes, onTap: onLike, color: liked ? C.ember : null),
        ActionBtn(icon: Icons.chat_bubble_outline_rounded, count: comments, onTap: onComment),
        ActionBtn(icon: Icons.ios_share_rounded, count: shares > 0 ? shares : null, onTap: onShare),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// Quiet icon + count button used in card action bars.
class ActionBtn extends StatelessWidget {
  const ActionBtn({super.key, required this.icon, required this.onTap, this.count, this.color});
  final IconData icon;
  final int? count;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 22,
    child: Padding(
      padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: color ?? C.inkSoft),
          if (count != null) ...[const SizedBox(width: 5), Text('$count', style: ui(12.5, color: color ?? C.inkSoft, w: 500))],
        ],
      ),
    ),
  );
}

/// Compact icon + text chip for card meta lines.
class InfoChip extends StatelessWidget {
  const InfoChip(this.icon, this.text, {super.key, this.color = C.inkSoft});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12.5, color: color))),
    ],
  );
}

/// Cover image area for feed cards: real photo with shimmer, else a flat neutral block with an icon.
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.media, required this.icon, this.height = 150, this.badge});
  final List<String> media;
  final IconData icon;
  final double height;
  final Widget? badge;
  @override
  Widget build(BuildContext context) {
    final photo = media.firstWhere((m) => !isVideoPath(m), orElse: () => '');
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetPhoto(photo, height: height, radius: 0, fallbackIcon: icon),
          if (badge != null) Positioned(left: 10, top: 10, child: badge!),
        ],
      ),
    );
  }
}

/// Flat white feed card with a hairline border.
class FeedCardShell extends StatelessWidget {
  const FeedCardShell({super.key, required this.child, this.onTap, this.dim = false, this.tint});
  final Color? tint;
  final Widget child;
  final VoidCallback? onTap;
  final bool dim;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dim ? 0.6 : 1,
    child: Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: tint ?? C.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line), boxShadow: const [BoxShadow(color: Color(0x0F1A1013), blurRadius: 18, offset: Offset(0, 6))]),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: child),
      ),
    ),
  );
}

/// A pill badge that sits on a cover photo.
class CoverBadge extends StatelessWidget {
  const CoverBadge(this.label, {super.key, this.icon, this.bg = Colors.white, this.fg = C.ink});
  final String label;
  final IconData? icon;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Tag(label, icon: icon, bg: bg, fg: fg);
}

/// One group of single-choice options in [showFilterSheet].
class FilterGroup {
  const FilterGroup(this.id, this.title, this.options, {this.selected, this.allLabel});
  final String id, title;
  final List<(String, String, IconData?)> options;
  final String? selected;

  /// When set, adds a leading "all" option that maps to null.
  final String? allLabel;
}

/// Bottom sheet of filter groups. Returns the chosen key per group id (null means "all"), or null if dismissed.
Future<Map<String, String?>?> showFilterSheet(BuildContext context, {required String title, required List<FilterGroup> groups}) {
  final sel = {for (final g in groups) g.id: g.selected};
  return showModalBottomSheet<Map<String, String?>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Text(title, style: ui(18, w: 600))),
                TextButton(
                  onPressed: () => setState(() {
                    for (final g in groups) {
                      sel[g.id] = g.allLabel != null ? null : g.options.first.$1;
                    }
                  }),
                  child: Text('Reset', style: ui(13, color: C.inkSoft, w: 600)),
                ),
              ],
            ),
            for (final g in groups) ...[
              const SizedBox(height: 8),
              Text(g.title, style: ui(12.5, color: C.inkSoft, w: 600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (g.allLabel != null) AppChip(label: g.allLabel!, selected: sel[g.id] == null, onTap: () => setState(() => sel[g.id] = null)),
                  for (final o in g.options)
                    AppChip(label: o.$2, icon: o.$3, selected: sel[g.id] == o.$1, onTap: () => setState(() => sel[g.id] = o.$1)),
                ],
              ),
            ],
            const SizedBox(height: 18),
            PillButton(label: 'Apply', onPressed: () => Navigator.pop(ctx, Map<String, String?>.from(sel))),
          ],
        ),
      ),
    ),
  );
}

/// Slim single-row header (title + actions) over one compact tab row, for list screens.
/// Floats away on scroll so cards start high.
class WelfareHeaderSliver extends StatelessWidget {
  const WelfareHeaderSliver({super.key, required this.title, required this.actions, required this.tabs, required this.tabIndex, required this.onTab, this.leading});
  final String title;
  final List<Widget> actions;
  final List<String> tabs;
  final int tabIndex;
  final ValueChanged<int> onTab;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => SliverAppBar(
    floating: true,
    snap: true,
    pinned: false,
    automaticallyImplyLeading: false,
    backgroundColor: Colors.transparent,
    flexibleSpace: frostedBarBackground(),
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    toolbarHeight: 52,
    titleSpacing: 0,
    title: AppTopBar(title: title, leading: leading, actions: actions, padding: const EdgeInsets.fromLTRB(16, 4, 8, 4)),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(40),
      child: CompactTabs(labels: tabs, index: tabIndex, onChanged: onTab),
    ),
  );
}

/// Same header for non-scrolling layouts (map mode).
class WelfareHeaderBox extends StatelessWidget {
  const WelfareHeaderBox({super.key, required this.title, required this.actions, required this.tabs, required this.tabIndex, required this.onTab, this.leading});
  final String title;
  final List<Widget> actions;
  final List<String> tabs;
  final int tabIndex;
  final ValueChanged<int> onTab;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white.withValues(alpha: 0.25),
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTopBar(title: title, leading: leading, actions: actions, padding: const EdgeInsets.fromLTRB(16, 4, 8, 4)),
        CompactTabs(labels: tabs, index: tabIndex, onChanged: onTab),
      ],
    ),
  );
}

/// Optimistic overlay: freshly changed objects shown instead of the (stale) fetched ones for a few seconds.
class OptimisticStore<T> extends Notifier<Map<int, (T, int)>> {
  @override
  Map<int, (T, int)> build() => {};
  void put(int id, T v) => state = {...state, id: (v, DateTime.now().millisecondsSinceEpoch)};
  void clear(int id) => state = {...state}..remove(id);
  T? fresh(int id) {
    final e = state[id];
    if (e == null) return null;
    return DateTime.now().millisecondsSinceEpoch - e.$2 < 8000 ? e.$1 : null;
  }
}

/// Bottom sheet with comments and a composer, generic over gatherings and donations.
Future<void> showCommentsSheet(
  BuildContext context, {
  required FutureProvider<List<Comment>> comments,
  required Future<void> Function(String body) onSend,
}) {
  return showWelfareSheet(
    context,
    builder: (_) => _CommentsBody(comments: comments, onSend: onSend),
  );
}

class _CommentsBody extends ConsumerStatefulWidget {
  const _CommentsBody({required this.comments, required this.onSend});
  final FutureProvider<List<Comment>> comments;
  final Future<void> Function(String body) onSend;
  @override
  ConsumerState<_CommentsBody> createState() => _CommentsBodyState();
}

class _CommentsBodyState extends ConsumerState<_CommentsBody> {
  final _text = TextEditingController();
  final _pending = <String>[];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Shows the comment straight away; on failure it is removed, restored in the box and a toast explains.
  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _pending.add(body));
    _text.clear();
    try {
      await widget.onSend(body);
      if (mounted) {
        await ref.read(widget.comments.future).catchError((_) => <Comment>[]);
      }
      if (mounted) setState(() => _pending.remove(body));
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending.remove(body));
      if (_text.text.isEmpty) _text.text = body;
      toastError(context, e, fallback: 'Could not post your comment. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(widget.comments);
    final h = MediaQuery.sizeOf(context).height;
    Widget row(Widget avatar, String name, String? when, String body, {bool faded = false, Widget? tag}) => Opacity(
      opacity: faded ? 0.5 : 1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(name, style: ui(13, w: 600)),
                    ?tag,
                    if (when != null) Text(when, style: ui(11.5, color: C.inkSoft)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(body, style: ui(14, h: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      height: h * 0.72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: Text('Comments', style: ui(18, w: 600))),
            const SizedBox(height: 10),
            Expanded(
              child: async.when(
                skipLoadingOnReload: true,
                loading: () => const RowListSkeleton(count: 3),
                error: (e, _) => SingleChildScrollView(child: ErrorState(error: e, onRetry: () => ref.invalidate(widget.comments))),
                data: (items) => items.isEmpty && _pending.isEmpty
                    ? Center(child: Text('Be the first to say something kind.', style: ui(14, color: C.inkSoft)))
                    : ListView(
                        children: [
                          for (final c in items) ...[
                            row(
                              PersonAvatar(c.author, size: 32),
                              c.author.label,
                              _ago(c.createdAt),
                              c.body,
                              tag: (c.author.role == 'admin' || c.author.role == 'neta')
                                  ? Tag(c.author.role == 'admin' ? 'Authority' : 'Neta', bg: C.muted)
                                  : null,
                            ),
                            const SizedBox(height: 14),
                          ],
                          for (final b in _pending) ...[
                            row(const Icon(Icons.schedule_rounded, size: 32, color: C.inkSoft), 'You', 'sending', b, faded: true),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: ui(14),
                    decoration: InputDecoration(
                      hintText: 'Add a comment',
                      isDense: true,
                      filled: true,
                      fillColor: C.muted,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  style: IconButton.styleFrom(backgroundColor: C.ink),
                  icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _ago(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

/// Re-runs [onTick] every [every] while mounted. Cancels itself on dispose.
mixin PollingState<T extends StatefulWidget> on State<T> {
  Timer? _poll;

  void startPolling(Duration every, VoidCallback onTick) {
    _poll?.cancel();
    _poll = Timer.periodic(every, (_) {
      if (mounted) onTick();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

/// Pull-to-refresh helper that bumps the welfare tick.
Future<void> refreshWelfare(WidgetRef ref) async {
  ref.read(welfareTickProvider.notifier).bump();
  await Future<void>.delayed(const Duration(milliseconds: 350));
}

/// Slim inline notice.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text, this.color = C.amber, this.onTap, this.cta});
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;
  final String? cta;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: C.ink),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: ui(12.5, h: 1.35))),
          if (onTap != null && cta != null) ...[
            const SizedBox(width: 8),
            GestureDetector(onTap: onTap, child: Text(cta!, style: ui(13, w: 600))),
          ],
        ],
      ),
    );
  }
}

/// Underlined tab row (one line, 40dp) that shrinks labels instead of overflowing.
class FitTabs extends StatelessWidget {
  const FitTabs({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey('tab-${labels[i]}'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i != index) {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  }
                },
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(labels[i], style: ui(13.5, color: i == index ? C.ink : C.inkSoft, w: i == index ? 600 : 500)),
                      ),
                    ),
                    Container(
                      height: 2.5,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: i == index ? C.ember : Colors.transparent, borderRadius: BorderRadius.circular(2)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}


/// Venue / pickup location chooser: a tidy tile that opens the map picker, then shows a preview.
/// When nothing is picked the form falls back to the user's current location.
class LocationField extends ConsumerWidget {
  const LocationField({super.key, required this.value, required this.onChanged, required this.address, this.title = 'Choose location'});
  final PickedLocation? value;
  final ValueChanged<PickedLocation> onChanged;
  final TextEditingController address;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(locationProvider);
    Future<void> pick() async {
      final init = value != null ? LatLng(value!.lat, value!.lng) : (loc.has ? LatLng(loc.lat!, loc.lng!) : null);
      final r = await showLocationPicker(context, initial: init, initialAddress: address.text, title: title);
      if (r == null) return;
      if (r.address.isNotEmpty) address.text = r.address;
      onChanged(r);
    }

    if (value != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MapPreview(lat: value!.lat, lng: value!.lng, height: 130, label: 'Chosen location', onTap: pick),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: pick,
            icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
            label: Text('Change on map', style: ui(13, w: 600)),
            style: TextButton.styleFrom(foregroundColor: C.ink, padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: pick,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.map_outlined, size: 18, color: loc.has ? C.ember : C.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loc.has ? 'Using your current location. Tap to choose on the map.' : 'Choose the location on the map',
                style: ui(13, h: 1.3),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: C.inkSoft),
          ],
        ),
      ),
    );
  }
}
