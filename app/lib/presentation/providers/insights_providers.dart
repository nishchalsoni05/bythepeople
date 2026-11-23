import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/insights_di.dart';
import 'package:by_the_people/domain/entities/insights.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';

final insightsProvider = FutureProvider<Insights>((ref) {
  ref.watch(tickProvider);
  return ref.read(insightsRepositoryProvider).insights();
});

final impactProvider = FutureProvider<Impact>((ref) {
  ref.watch(tickProvider);
  return ref.read(insightsRepositoryProvider).impact();
});
