import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/app_update/model/app_update_failure.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/utils/utils.dart';

abstract interface class AppUpdateRepository {
  TaskEither<AppUpdateFailure, RemoteVersionEntity> getLatestVersion({
    bool includePreReleases = false,
    Release release = Release.general,
  });
}

class AppUpdateRepositoryImpl with ExceptionHandler, InfraLogger implements AppUpdateRepository {
  AppUpdateRepositoryImpl({required this.httpClient});

  final DioHttpClient httpClient;

  @override
  TaskEither<AppUpdateFailure, RemoteVersionEntity> getLatestVersion({
    bool includePreReleases = false,
    Release release = Release.general,
  }) {
    return exceptionHandler(() async {
      if (!release.allowCustomUpdateChecker) {
        throw Exception("custom update checkers are not supported");
      }
      // This fork updates from the dai-owned manifest, not the upstream
      // Hiddify releases: the upstream APK has a different package/signature
      // and can never install over ai.bigt.vpn.
      final response = await httpClient.get<dynamic>(Constants.updateManifestUrl);
      final data = response.data is Map ? (response.data as Map).cast<String, dynamic>() : null;
      if (response.statusCode != 200 || data == null) {
        loggy.warning("failed to fetch latest version info");
        return left(const AppUpdateFailure.unexpected());
      }

      final version = data['versionName'] as String?;
      final assets = [
        for (final raw in (data['assets'] as List? ?? const []))
          if (raw is Map && raw['name'] is String && raw['url'] is String)
            ReleaseAsset(
              name: raw['name'] as String,
              url: raw['url'] as String,
              size: (raw['size'] as num?)?.toInt() ?? 0,
              digest: raw['sha256'] is String ? 'sha256:${raw['sha256']}' : null,
            ),
      ];
      if (version == null || version.isEmpty || assets.isEmpty) {
        return left(const AppUpdateFailure.unexpected());
      }
      return right(
        RemoteVersionEntity(
          version: version,
          buildNumber: '${data['versionCode'] ?? ''}',
          releaseTag: 'v$version',
          preRelease: false,
          url: Constants.updateManifestUrl,
          publishedAt: DateTime.tryParse('${data['publishedAt'] ?? ''}') ?? DateTime.now(),
          flavor: Environment.prod,
          assets: assets,
          changelog: data['changelog'] as String?,
        ),
      );
    }, AppUpdateFailure.unexpected);
  }
}
