import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/data/repositories/donation_repository_impl.dart';
import 'package:by_the_people/data/repositories/foundation_repository_impl.dart';
import 'package:by_the_people/data/repositories/gathering_repository_impl.dart';
import 'package:by_the_people/domain/repositories/welfare_repositories.dart';

/// Composition root for gatherings, donations and foundations.

final gatheringRepositoryProvider = Provider<GatheringRepository>((ref) => GatheringRepositoryImpl(ref.watch(apiClientProvider)));

final donationRepositoryProvider = Provider<DonationRepository>((ref) => DonationRepositoryImpl(ref.watch(apiClientProvider)));

final foundationRepositoryProvider = Provider<FoundationRepository>((ref) => FoundationRepositoryImpl(ref.watch(apiClientProvider)));

final mediaRepositoryProvider = Provider<MediaRepository>((ref) => MediaRepositoryImpl(ref.watch(apiClientProvider)));

/// A photo chosen by the user, ready to upload.
class PickedPhoto {
  final List<int> bytes;
  final String mime;
  const PickedPhoto(this.bytes, this.mime);
}

/// Device features behind an interface so tests can replace them.
abstract class WelfarePlatform {
  /// Returns null when the user cancels.
  Future<PickedPhoto?> pickPhoto({required bool camera});
  Future<void> share(String text);
}

class DeviceWelfarePlatform implements WelfarePlatform {
  const DeviceWelfarePlatform();

  @override
  Future<PickedPhoto?> pickPhoto({required bool camera}) async {
    final file = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (file == null) return null;
    final name = file.name.toLowerCase();
    final mime = name.endsWith('.png') ? 'image/png' : (name.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
    return PickedPhoto(await file.readAsBytes(), mime);
  }

  @override
  Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

final welfarePlatformProvider = Provider<WelfarePlatform>((ref) => const DeviceWelfarePlatform());
