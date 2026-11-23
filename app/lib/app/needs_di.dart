import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/data/repositories/needs_repository_impl.dart';
import 'package:by_the_people/domain/repositories/needs_repository.dart';

/// Composition root for the needs board. Kept apart from di.dart so each feature owns its wiring.
final needsRepositoryProvider = Provider<NeedsRepository>((ref) => NeedsRepositoryImpl(ref.watch(apiClientProvider)));
