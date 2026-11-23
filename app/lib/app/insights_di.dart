import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/data/repositories/insights_repository_impl.dart';
import 'package:by_the_people/domain/repositories/insights_repository.dart';

/// Composition root for insights. Kept apart from di.dart so each feature owns its wiring.
final insightsRepositoryProvider =
    Provider<InsightsRepository>((ref) => InsightsRepositoryImpl(ref.watch(apiClientProvider)));
