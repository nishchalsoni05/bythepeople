/// A point on the map, in degrees.
class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);

  /// Key with ~100 m precision, used to avoid refetching on tiny GPS jitter.
  String get coarseKey => '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
}

/// Which geography the user is looking at: city, state or region. [areaId] null means "where I am".
class ScopeFilter {
  final String kind;
  final int? areaId;
  const ScopeFilter(this.kind, [this.areaId]);

  Map<String, dynamic> toQuery() => {'scope': kind, if (areaId != null) 'areaId': areaId};
}

/// What the user is filing in the report flow.
class ReportDraft {
  final String title;
  final String category;
  final String description;
  final GeoPoint location;
  final int? linkTo;
  final String? address;
  final List<String> media;

  const ReportDraft({
    required this.title,
    required this.category,
    required this.description,
    required this.location,
    this.linkTo,
    this.address,
    this.media = const [],
  });
}
