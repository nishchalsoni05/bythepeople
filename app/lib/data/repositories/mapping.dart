import 'package:by_the_people/domain/entities/query.dart';

/// Query-string fragment for an optional position. Empty when there is no position.
Map<String, dynamic> geoQuery(GeoPoint? at) => at == null ? const {} : {'lat': at.lat, 'lng': at.lng};
