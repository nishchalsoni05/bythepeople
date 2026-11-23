import 'package:by_the_people/domain/entities/insights.dart';

/// Insights for the signed-in user and community impact totals.
abstract interface class InsightsRepository {
  Future<Insights> insights();
  Future<Impact> impact();
}
