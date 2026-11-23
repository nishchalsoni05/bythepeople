import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/config/env.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/network/token_store.dart';
import 'package:by_the_people/data/repositories/auth_repository_impl.dart';
import 'package:by_the_people/data/repositories/geo_catalog_repository_impl.dart';
import 'package:by_the_people/data/repositories/issue_repository_impl.dart';
import 'package:by_the_people/data/repositories/media_portal_repository_impl.dart';
import 'package:by_the_people/data/repositories/neta_notification_system_repository_impl.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';

/// Composition root: the only place that knows concrete implementations.

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(baseUrl: Env.apiBaseUrl));

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);

final geoRepositoryProvider = Provider<GeoRepository>((ref) => GeoRepositoryImpl(ref.watch(apiClientProvider)));

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => CatalogRepositoryImpl(ref.watch(apiClientProvider)));

final issueRepositoryProvider = Provider<IssueRepository>((ref) => IssueRepositoryImpl(ref.watch(apiClientProvider)));

final netaRepositoryProvider = Provider<NetaRepository>((ref) => NetaRepositoryImpl(ref.watch(apiClientProvider)));

final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) => NotificationRepositoryImpl(ref.watch(apiClientProvider)));

final systemRepositoryProvider = Provider<SystemRepository>((ref) => SystemRepositoryImpl(ref.watch(apiClientProvider)));

final mediaUploadRepositoryProvider = Provider<MediaUploadRepository>((ref) => MediaUploadRepositoryImpl(ref.watch(apiClientProvider)));

final portalRepositoryProvider = Provider<PortalRepository>((ref) => PortalRepositoryImpl(ref.watch(apiClientProvider)));
