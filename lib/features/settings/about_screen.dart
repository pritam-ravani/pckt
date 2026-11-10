import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme/icons.dart';
import '../../ui/brand_mark.dart';
import '../../ui/widgets.dart';

/// Version, attribution and the legal notices GPL-3.0 asks an interactive
/// program to show.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          const Center(child: BrandMark(size: 72)),
          const SizedBox(height: 12),
          Center(child: Text(AppInfo.name, style: text.headlineSmall)),
          Center(child: Text('Version ${AppInfo.version}', style: text.bodyMedium)),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Based on Pckt by pritam-ravani, modified since November 2026.'),
                const SelectableText(AppInfo.upstreamUrl),
                const SizedBox(height: 12),
                const Text('Copyright © the Pckt authors and PennyWise contributors.'),
                const SizedBox(height: 12),
                const Text(
                  'This program is free software under the GNU General Public License, version 3. '
                  'It comes with ABSOLUTELY NO WARRANTY. You may share and change it under the '
                  'terms of that licence.',
                ),
                const SizedBox(height: 12),
                Text('Source code', style: text.titleMedium),
                const SelectableText(AppInfo.sourceUrl),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: ListTile(
              leading: const Icon(PhosphorIconsRegular.listBullets),
              title: const Text('Open-source licences'),
              subtitle: const Text('GPL-3.0, packages and fonts'),
              trailing: const Icon(PhosphorIconsBold.caretRight, size: 16),
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppInfo.name,
                applicationVersion: AppInfo.version,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
