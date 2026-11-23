import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/media.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Largest upload the server accepts (decoded).
const maxUploadBytes = 12 * 1024 * 1024;

/// Network image with a soft placeholder and a graceful fallback.
class NetImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width, height;

  /// Shown (on a neutral tile) when the image cannot load. Defaults to a broken-image glyph.
  final IconData? fallbackIcon;
  const NetImage(this.path, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      mediaUrl(path),
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: frame == null && !sync ? 0 : 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: child,
      ),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Skeleton(child: Container(width: width, height: height, color: C.line)),
      errorBuilder: (_, _, _) => Container(
        width: width,
        height: height,
        color: C.muted,
        alignment: Alignment.center,
        child: Icon(fallbackIcon ?? Icons.image_not_supported_outlined, color: C.inkSoft.withValues(alpha: 0.6), size: 28),
      ),
    );
  }
}

/// Swipeable photo/video gallery. Tap to open full screen.
class MediaGallery extends StatefulWidget {
  final List<String> media;
  final double height;
  final double radius;
  final bool tapToOpen;
  final IconData? fallbackIcon;
  const MediaGallery({super.key, required this.media, this.height = 220, this.radius = 12, this.tapToOpen = true, this.fallbackIcon});
  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    if (m.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [
          PageView.builder(
            itemCount: m.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.tapToOpen ? () => openMediaViewer(context, m, i) : null,
              child: isVideoPath(m[i])
                  ? Stack(fit: StackFit.expand, children: [
                      Container(color: C.inkCard),
                      Center(
                        child: Container(
                          width: 56, height: 56,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, size: 32, color: C.ink),
                        ),
                      ),
                      const Positioned(left: 12, bottom: 12, child: _Tag(icon: Icons.videocam_rounded, text: 'Video')),
                    ])
                  : NetImage(m[i], fallbackIcon: widget.fallbackIcon),
            ),
          ),
          if (m.length > 1)
            Positioned(
              top: 10, right: 10,
              child: _Tag(text: '${_i + 1}/${m.length}'),
            ),
          if (m.length > 1)
            Positioned(
              bottom: 10, left: 0, right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var d = 0; d < m.length; d++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: d == _i ? 16 : 6, height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(color: d == _i ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(6)),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData? icon;
  final String text;
  const _Tag({this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 4)],
          Text(text, style: ui(11.5, color: Colors.white, w: 700)),
        ]),
      );
}

void openMediaViewer(BuildContext context, List<String> media, int index) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => MediaViewer(media: media, index: index),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class MediaViewer extends StatefulWidget {
  final List<String> media;
  final int index;
  const MediaViewer({super.key, required this.media, required this.index});
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _c = PageController(initialPage: widget.index);
  late int _i = widget.index;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _c,
          itemCount: widget.media.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => isVideoPath(widget.media[i])
              ? VideoPlayerView(url: mediaUrl(widget.media[i]), autoplay: i == widget.index)
              : InteractiveViewer(minScale: 1, maxScale: 4, child: Center(child: NetImage(widget.media[i], fit: BoxFit.contain))),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8, left: 12, right: 12,
          child: Row(children: [
            CircleBtn(icon: Icons.close_rounded, dark: true, size: 42, onTap: () => Navigator.pop(context)),
            const Spacer(),
            if (widget.media.length > 1) _Tag(text: '${_i + 1}/${widget.media.length}'),
          ]),
        ),
      ]),
    );
  }
}

/// Network video with tap-to-play and a thin progress bar.
class VideoPlayerView extends StatefulWidget {
  final String url;
  final bool autoplay;
  const VideoPlayerView({super.key, required this.url, this.autoplay = false});
  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.setLooping(true);
      if (widget.autoplay) _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const Center(child: Text('Video could not be played', style: TextStyle(color: Colors.white70)));
    if (!_ready) return const Center(child: CircularProgressIndicator(color: Colors.white));
    final playing = _c.value.isPlaying;
    return GestureDetector(
      onTap: () => playing ? _c.pause() : _c.play(),
      child: Stack(alignment: Alignment.center, children: [
        Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c))),
        AnimatedOpacity(
          opacity: playing ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, size: 38, color: C.ink),
          ),
        ),
        Positioned(
          left: 24, right: 24, bottom: MediaQuery.of(context).padding.bottom + 24,
          child: VideoProgressIndicator(_c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: C.ember, bufferedColor: Colors.white30, backgroundColor: Colors.white12)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Picking and uploading
// ---------------------------------------------------------------------------

class PickedMedia {
  final XFile file;
  final bool video;
  final Uint8List? preview; // image bytes for thumbnails
  PickedMedia(this.file, this.video, this.preview);
  String get mime => video ? (file.path.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4') : mimeForPath(file.path);
}

/// Holds the photos and videos a user attached to a form, and uploads them on submit.
class MediaAttachController extends ChangeNotifier {
  MediaAttachController({this.max = 4, this.allowVideo = true});
  final int max;
  final bool allowVideo;
  final List<PickedMedia> items = [];
  bool _uploading = false;
  bool get uploading => _uploading;
  bool get full => items.length >= max;

  final _picker = ImagePicker();

  Future<void> add(BuildContext context) async {
    if (full) return;
    final choice = await showModalBottomSheet<_Source>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SourceSheet(allowVideo: allowVideo),
    );
    if (choice == null) return;
    try {
      XFile? f;
      switch (choice) {
        case _Source.camera:
          f = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 82);
        case _Source.gallery:
          f = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
        case _Source.recordVideo:
          f = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
        case _Source.galleryVideo:
          f = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
      }
      if (f == null) return;
      final video = choice == _Source.recordVideo || choice == _Source.galleryVideo;
      final len = await f.length();
      if (len > maxUploadBytes) {
        if (context.mounted) showToast(context, 'That file is over 12 MB. Pick a shorter clip or a smaller photo.', error: true);
        return;
      }
      items.add(PickedMedia(f, video, video ? null : await f.readAsBytes()));
      notifyListeners();
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not open the camera or library. Check app permissions.', error: true);
    }
  }

  void remove(int i) {
    items.removeAt(i);
    notifyListeners();
  }

  void clear() {
    items.clear();
    notifyListeners();
  }

  /// Uploads every attachment and returns their server paths. Throws [ApiException] on failure.
  Future<List<String>> upload(Future<String> Function(Uint8List bytes, String mime) uploadOne) async {
    _uploading = true;
    notifyListeners();
    try {
      final out = <String>[];
      for (final m in items) {
        out.add(await uploadOne(await m.file.readAsBytes(), m.mime));
      }
      return out;
    } on ApiException {
      rethrow;
    } finally {
      _uploading = false;
      notifyListeners();
    }
  }
}

enum _Source { camera, gallery, recordVideo, galleryVideo }

class _SourceSheet extends StatelessWidget {
  final bool allowVideo;
  const _SourceSheet({required this.allowVideo});
  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String label, _Source s) => TapScale(
          onTap: () => Navigator.pop(context, s),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              Icon(icon, size: 22, color: C.ember),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: ui(15, w: 700))),
            ]),
          ),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(color: C.canvas, borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        Text('Add photo or video', style: ui(18, w: 750)),
        const SizedBox(height: 12),
        tile(Icons.photo_camera_rounded, 'Take a photo', _Source.camera),
        tile(Icons.photo_library_rounded, 'Choose a photo', _Source.gallery),
        if (allowVideo) tile(Icons.videocam_rounded, 'Record a video', _Source.recordVideo),
        if (allowVideo) tile(Icons.video_library_rounded, 'Choose a video', _Source.galleryVideo),
      ]),
    );
  }
}

/// Thumbnail row for a [MediaAttachController].
class MediaAttachStrip extends StatelessWidget {
  final MediaAttachController controller;
  final String addLabel;
  const MediaAttachStrip({super.key, required this.controller, this.addLabel = 'Add photo or video'});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.items;
        return SizedBox(
          height: 84,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 6),
                child: Stack(clipBehavior: Clip.none, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 72, height: 72,
                      child: items[i].preview != null
                          ? Image.memory(items[i].preview!, fit: BoxFit.cover)
                          : Container(color: C.inkCard, child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30)),
                    ),
                  ),
                  Positioned(
                    top: -6, right: -6,
                    child: GestureDetector(
                      onTap: () => controller.remove(i),
                      child: Container(
                        width: 24, height: 24,
                        decoration: const BoxDecoration(color: C.ink, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              ),
            if (!controller.full)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TapScale(
                  onTap: () => controller.add(context),
                  child: Container(
                    height: 72,
                    constraints: const BoxConstraints(minWidth: 72),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18), boxShadow: softShadow),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_a_photo_rounded, size: 22, color: C.ember),
                      if (items.isEmpty) ...[const SizedBox(width: 10), Text(addLabel, style: ui(13.5, w: 700))],
                    ]),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}
