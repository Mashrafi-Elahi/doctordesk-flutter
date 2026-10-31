import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateChecker {
  const UpdateChecker._();

  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final config = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('android')
          .get();
      final data = config.data();
      if (data == null) return;

      final latestVersion = data['latestVersion'] as String?;
      final minVersion = data['minVersion'] as String?;
      final apkUrl = data['apkUrl'] as String?;
      final notes = data['notes'] as String? ?? '';
      if (latestVersion == null || minVersion == null || apkUrl == null) return;

      final currentVersion = (await PackageInfo.fromPlatform()).version;
      if (_compareVersions(currentVersion, latestVersion) >= 0 ||
          !context.mounted) {
        return;
      }

      final isForced = _compareVersions(currentVersion, minVersion) < 0;
      await showDialog<void>(
        context: context,
        barrierDismissible: !isForced,
        builder: (dialogContext) => PopScope(
          canPop: !isForced,
          child: AlertDialog(
            title: const Text('Update available'),
            content: Text(notes.isEmpty ? 'A newer version is available.' : notes),
            actions: [
              if (!isForced)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Later'),
                ),
              FilledButton(
                onPressed: () async {
                  try {
                    await launchUrl(
                      Uri.parse(apkUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {}
                },
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // Update checks must never interrupt normal offline use.
    }
  }

  static int _compareVersions(String first, String second) {
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
