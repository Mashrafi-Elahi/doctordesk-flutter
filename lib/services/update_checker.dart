import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks Firestore `app_config/android` for newer app versions and prompts
/// the user to download the update.
class UpdateChecker {
  const UpdateChecker._();

  static bool _hasCheckedThisSession = false;

  /// Triggered on app launch. Runs once per session to avoid nag loops.
  static Future<void> checkForUpdate(BuildContext context) async {
    if (_hasCheckedThisSession) return;
    _hasCheckedThisSession = true;

    try {
      final config = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('android')
          .get();
      final data = config.data();
      if (data == null) return;

      final latestVersion = data['latestVersion']?.toString();
      final apkUrl = data['apkUrl']?.toString();
      final notes = data['notes']?.toString() ?? '';
      if (latestVersion == null || apkUrl == null || apkUrl.isEmpty) return;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final latestBuildNumber = (data['latestBuildNumber'] as num?)?.toInt() ??
          _extractBuildNumber(latestVersion);

      // Compare semantic version and pubspec build number
      final isNewer = _isVersionNewer(
        currentVersion: currentVersion,
        currentBuild: currentBuildNumber,
        targetVersion: latestVersion,
        targetBuild: latestBuildNumber,
      );

      if (!isNewer || !context.mounted) {
        return;
      }

      final minVersion = data['minVersion']?.toString();
      final minBuildNumber = (data['minBuildNumber'] as num?)?.toInt() ??
          (minVersion != null ? _extractBuildNumber(minVersion) : null);

      final isCritical = minVersion != null &&
          _isVersionNewer(
            currentVersion: currentVersion,
            currentBuild: currentBuildNumber,
            targetVersion: minVersion,
            targetBuild: minBuildNumber,
          );

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update available'),
          content: Text(
            notes.trim().isNotEmpty
                ? notes
                : 'A newer version of DoctorDesk is available. Tap Download to install the latest APK.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(isCritical ? 'Dismiss' : 'Later'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await launchUrl(
                    Uri.parse(apkUrl),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (_) {}
              },
              child: const Text('Download'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Update checks must never interrupt normal offline use.
    }
  }

  /// Extracts build number from a string like "1.0.1+2" -> 2
  static int? _extractBuildNumber(String version) {
    if (version.contains('+')) {
      final parts = version.split('+');
      if (parts.length > 1) {
        return int.tryParse(parts[1].split(RegExp(r'[^0-9]')).first);
      }
    }
    return null;
  }

  /// Returns true if target version/build is strictly newer than current.
  static bool _isVersionNewer({
    required String currentVersion,
    required int currentBuild,
    required String targetVersion,
    int? targetBuild,
  }) {
    final cmp = _compareSemver(currentVersion, targetVersion);
    if (cmp < 0) return true; // Target semver is higher
    if (cmp > 0) return false; // Current semver is higher

    // Semver is equal -> compare build numbers
    final tBuild = targetBuild ?? _extractBuildNumber(targetVersion) ?? 0;
    return currentBuild < tBuild;
  }

  /// Compares semantic version strings (e.g. "1.0.0" vs "1.0.1")
  static int _compareSemver(String first, String second) {
    final firstParts = _versionParts(first);
    final secondParts = _versionParts(second);
    final length = firstParts.length > secondParts.length
        ? firstParts.length
        : secondParts.length;

    for (var index = 0; index < length; index++) {
      final firstPart = index < firstParts.length ? firstParts[index] : 0;
      final secondPart = index < secondParts.length ? secondParts[index] : 0;
      if (firstPart != secondPart) return firstPart.compareTo(secondPart);
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    final normalized = version.split(RegExp(r'[+-]')).first;
    return normalized
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }
}
