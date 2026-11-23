import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

export 'package:latlong2/latlong.dart' show LatLng;

const _osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _pkg = 'com.bythepeople.app';

/// Result of [showLocationPicker].
class PickedLocation {
  final double lat, lng;
  final String address;
  const PickedLocation(this.lat, this.lng, this.address);
}

/// One pin on a [MarkersMapScreen] / [FullMapScreen].
class MapItem {
  final String id, title;
  final String? subtitle, typeLabel;
  final double lat, lng;
  final Color color;
  final IconData icon;
  final Object? data;
  const MapItem({
    required this.id, required this.title, required this.lat, required this.lng,
    this.subtitle, this.typeLabel, this.color = C.ember, this.icon = Icons.place_rounded, this.data,
  });
}

Future<void> openInMaps(double lat, double lng, {String? label, bool directions = false}) async {
  final q = label == null ? '$lat,$lng' : '$lat,$lng(${Uri.encodeComponent(label)})';
  final uris = directions
      ? [Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng')]
      : [Uri.parse('geo:$lat,$lng?q=$q'), Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng')];
  for (final u in uris) {
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
  }
}

TileLayer _tiles() => TileLayer(
      urlTemplate: _osmTiles,
      userAgentPackageName: _pkg,
      maxNativeZoom: 19,
      errorTileCallback: (tile, error, stack) {},
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
    );

class _Attribution extends StatelessWidget {
  const _Attribution();
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .8), borderRadius: BorderRadius.circular(4)),
          child: Text('© OpenStreetMap contributors', style: ui(9.5, color: C.inkSoft)),
        ),
      );
}

/// Neutral grid shown behind tiles: it is what the user sees offline or while tiles load.
class _OfflineBackdrop extends StatelessWidget {
  const _OfflineBackdrop();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter(), child: const SizedBox.expand());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFEDEBE5));
    final p = Paint()..color = const Color(0xFFE0DDD5)..strokeWidth = 1;
    for (double x = 0; x < s.width; x += 32) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (double y = 0; y < s.height; y += 32) {
      c.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Pin extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double size;
  const _Pin({this.color = C.ember, this.icon = Icons.place_rounded, this.size = 34});
  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.topCenter, children: [
        Positioned(
          bottom: 0,
          child: Container(width: 8, height: 3, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4))),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Container(
            width: size * .78,
            height: size * .78,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Icon(icon, size: size * .44, color: Colors.white),
          ),
        ),
      ]);
}

Marker _marker(LatLng p, Widget child, {double size = 34}) =>
    Marker(point: p, width: size, height: size, alignment: Alignment.topCenter, child: child);

/// Static, non-interactive map thumbnail with a marker. Tap opens [FullMapScreen] (or [onTap]).
class MapPreview extends StatelessWidget {
  final double lat, lng, height;
  final String? label;
  final VoidCallback? onTap;
  const MapPreview({super.key, required this.lat, required this.lng, this.height = 160, this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LatLng(lat, lng);
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FullMapScreen(lat: lat, lng: lng, label: label))),
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Stack(children: [
          const Positioned.fill(child: _OfflineBackdrop()),
          IgnorePointer(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: p,
                initialZoom: 15.5,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                backgroundColor: Colors.transparent,
              ),
              children: [
                _tiles(),
                MarkerLayer(markers: [_marker(p, const _Pin())]),
              ],
            ),
          ),
          const _Attribution(),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.open_in_full_rounded, size: 12, color: C.inkSoft),
                const SizedBox(width: 4),
                Text(label ?? 'View map', style: ui(11.5, w: 600), maxLines: 1),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  const _RoundBtn(this.icon, this.onTap, this.tooltip);
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: IconButton(icon: Icon(icon, size: 20, color: C.ink), tooltip: tooltip, onPressed: onTap),
      );
}

/// Interactive full-screen map of one point (or several [markers]).
class FullMapScreen extends StatefulWidget {
  final double lat, lng;
  final String? label, address;
  final List<MapItem> markers;
  const FullMapScreen({super.key, required this.lat, required this.lng, this.label, this.address, this.markers = const []});

  @override
  State<FullMapScreen> createState() => _FullMapScreenState();
}

class _FullMapScreenState extends State<FullMapScreen> {
  final _ctrl = MapController();

  @override
  Widget build(BuildContext context) {
    final p = LatLng(widget.lat, widget.lng);
    final items = widget.markers;
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: _OfflineBackdrop()),
        FlutterMap(
          mapController: _ctrl,
          options: MapOptions(
            initialCenter: p,
            initialZoom: 16,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: Colors.transparent,
            initialCameraFit: items.length > 1
                ? CameraFit.coordinates(
                    coordinates: [for (final m in items) LatLng(m.lat, m.lng)],
                    padding: const EdgeInsets.all(60),
                    maxZoom: 16,
                  )
                : null,
          ),
          children: [
            _tiles(),
            MarkerLayer(markers: [
              if (items.isEmpty) _marker(p, const _Pin(size: 44), size: 44),
              for (final m in items) _marker(LatLng(m.lat, m.lng), _Pin(color: m.color, icon: m.icon, size: 40), size: 40),
            ]),
          ],
        ),
        const _Attribution(),
        Positioned(left: 12, top: pad.top + 8, child: _RoundBtn(Icons.arrow_back_rounded, () => Navigator.pop(context), 'Back')),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 14, 16, pad.bottom + 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 12)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.label != null) Text(widget.label!, style: ui(16, w: 600), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (widget.address != null && widget.address!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(widget.address!, style: ui(13, color: C.inkSoft), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openInMaps(widget.lat, widget.lng, label: widget.label),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Open in Maps'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => openInMaps(widget.lat, widget.lng, label: widget.label, directions: true),
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Directions'),
                    style: FilledButton.styleFrom(backgroundColor: C.ink),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Full-screen location picker: centre pin, drag the map to choose.
/// Optionally constrain to [radiusKm] around [limitCenter] (shown as a ring).
Future<PickedLocation?> showLocationPicker(
  BuildContext context, {
  LatLng? initial,
  LatLng? limitCenter,
  double? radiusKm,
  String? initialAddress,
  String title = 'Choose location',
}) =>
    Navigator.of(context).push<PickedLocation>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _LocationPicker(initial: initial, limitCenter: limitCenter, radiusKm: radiusKm, initialAddress: initialAddress, title: title),
    ));

class _LocationPicker extends ConsumerStatefulWidget {
  final LatLng? initial, limitCenter;
  final double? radiusKm;
  final String? initialAddress;
  final String title;
  const _LocationPicker({this.initial, this.limitCenter, this.radiusKm, this.initialAddress, required this.title});
  @override
  ConsumerState<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<_LocationPicker> {
  final _ctrl = MapController();
  late final _addr = TextEditingController(text: widget.initialAddress ?? '');
  late LatLng _center;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final loc = ref.read(locationProvider);
    _center = widget.initial ?? (loc.has ? LatLng(loc.lat!, loc.lng!) : const LatLng(21.2514, 81.6296));
  }

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  bool get _outside {
    if (widget.limitCenter == null || widget.radiusKm == null) return false;
    return const Distance().as(LengthUnit.Kilometer, widget.limitCenter!, _center) > widget.radiusKm!;
  }

  Future<void> _useMine() async {
    setState(() => _locating = true);
    await ref.read(locationProvider.notifier).refresh();
    if (!mounted) return;
    final l = ref.read(locationProvider);
    setState(() => _locating = false);
    if (l.has && !l.fallback) {
      final p = LatLng(l.lat!, l.lng!);
      _ctrl.move(p, 17);
      setState(() => _center = p);
    } else {
      showToast(context, 'Could not get your location. Check location access.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final outside = _outside;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        const Positioned.fill(child: _OfflineBackdrop()),
        FlutterMap(
          mapController: _ctrl,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 16.5,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: Colors.transparent,
            onPositionChanged: (cam, _) => setState(() => _center = cam.center),
          ),
          children: [
            _tiles(),
            if (widget.limitCenter != null && widget.radiusKm != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: widget.limitCenter!,
                  radius: widget.radiusKm! * 1000,
                  useRadiusInMeter: true,
                  color: C.ember.withValues(alpha: .06),
                  borderColor: C.ember.withValues(alpha: .7),
                  borderStrokeWidth: 1.5,
                ),
              ]),
          ],
        ),
        const IgnorePointer(child: Center(child: Padding(padding: EdgeInsets.only(bottom: 44), child: _Pin(size: 52)))),
        const _Attribution(),
        Positioned(left: 12, top: pad.top + 8, child: _RoundBtn(Icons.close_rounded, () => Navigator.pop(context), 'Close')),
        Positioned(
          top: pad.top + 16,
          left: 64,
          right: 64,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)]),
              child: Text(widget.title, style: ui(13, w: 600)),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 190 + kb + pad.bottom,
          child: _locating
              ? const Material(color: Colors.white, shape: CircleBorder(), child: Padding(padding: EdgeInsets.all(13), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
              : _RoundBtn(Icons.my_location_rounded, _useMine, 'Use my location'),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: kb,
          child: Container(
            padding: EdgeInsets.fromLTRB(16, 14, 16, pad.bottom + 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 12)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _addr,
                textInputAction: TextInputAction.done,
                style: ui(14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Address or landmark (optional)',
                  prefixIcon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.line)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                outside ? 'Outside the allowed ${widget.radiusKm!.toStringAsFixed(widget.radiusKm! % 1 == 0 ? 0 : 1)} km range' : '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
                style: ui(12, color: outside ? C.ember : C.inkSoft),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: outside ? null : () => Navigator.pop(context, PickedLocation(_center.latitude, _center.longitude, _addr.text.trim())),
                  style: FilledButton.styleFrom(backgroundColor: C.ink, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Confirm location'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Map of many items with coloured markers and a bottom card on tap.
class MarkersMapScreen extends StatefulWidget {
  final String title;
  final List<MapItem> items;
  final void Function(BuildContext context, MapItem item)? onOpen;
  final String openLabel;
  const MarkersMapScreen({super.key, required this.items, this.title = 'Map', this.onOpen, this.openLabel = 'View details'});

  /// Embeddable body (no scaffold) for list/map toggles.
  static Widget body({Key? key, required List<MapItem> items, void Function(BuildContext, MapItem)? onOpen, String openLabel = 'View details'}) =>
      _MarkersMapBody(key: key, items: items, onOpen: onOpen, openLabel: openLabel);

  @override
  State<MarkersMapScreen> createState() => _MarkersMapScreenState();
}

class _MarkersMapScreenState extends State<MarkersMapScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title, style: ui(18, w: 600)), backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0),
        body: _MarkersMapBody(items: widget.items, onOpen: widget.onOpen, openLabel: widget.openLabel),
      );
}

class _MarkersMapBody extends ConsumerStatefulWidget {
  final List<MapItem> items;
  final void Function(BuildContext, MapItem)? onOpen;
  final String openLabel;
  const _MarkersMapBody({super.key, required this.items, this.onOpen, required this.openLabel});
  @override
  ConsumerState<_MarkersMapBody> createState() => _MarkersMapBodyState();
}

class _MarkersMapBodyState extends ConsumerState<_MarkersMapBody> {
  MapItem? _sel;

  @override
  Widget build(BuildContext context) {
    final items = widget.items.where((m) => m.lat != 0 || m.lng != 0).toList();
    final loc = ref.watch(locationProvider);
    final me = loc.has ? LatLng(loc.lat!, loc.lng!) : null;
    final center = items.isNotEmpty ? LatLng(items.first.lat, items.first.lng) : (me ?? const LatLng(21.2514, 81.6296));
    final sel = _sel;
    return Stack(children: [
      const Positioned.fill(child: _OfflineBackdrop()),
      FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 13,
          minZoom: 3,
          maxZoom: 19,
          backgroundColor: Colors.transparent,
          onTap: (_, _) => setState(() => _sel = null),
          initialCameraFit: items.length > 1
              ? CameraFit.coordinates(coordinates: [for (final m in items) LatLng(m.lat, m.lng)], padding: const EdgeInsets.all(56), maxZoom: 16)
              : null,
        ),
        children: [
          _tiles(),
          MarkerLayer(markers: [
            if (me != null)
              Marker(
                point: me,
                width: 18,
                height: 18,
                child: Container(decoration: BoxDecoration(color: const Color(0xFF2F7DE1), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 4)])),
              ),
            for (final m in items)
              Marker(
                point: LatLng(m.lat, m.lng),
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _sel = m),
                  child: _Pin(color: m.color, icon: m.icon, size: identical(m, sel) ? 46 : 40),
                ),
              ),
          ]),
        ],
      ),
      const _Attribution(),
      if (items.isEmpty)
        Center(child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text('Nothing to show on the map yet', style: ui(13, color: C.inkSoft)))),
      if (sel != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.of(context).padding.bottom,
          child: Material(
            color: Colors.white,
            elevation: 4,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onOpen == null ? null : () => widget.onOpen!(context, sel),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: sel.color.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)), child: Icon(sel.icon, color: sel.color, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      if (sel.typeLabel != null) Text(sel.typeLabel!, style: ui(11.5, color: sel.color, w: 600)),
                      Text(sel.title, style: ui(15, w: 600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (sel.subtitle != null) Text(sel.subtitle!, style: ui(12.5, color: C.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  if (widget.onOpen != null) const Icon(Icons.chevron_right_rounded, color: C.inkSoft),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}
