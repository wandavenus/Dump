import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/services/app_update_service.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/widgets/common/scrolling_page_chrome.dart';

class AppUpdateSettingsPage extends StatefulWidget {
  const AppUpdateSettingsPage({super.key});

  @override
  State<AppUpdateSettingsPage> createState() => _AppUpdateSettingsPageState();
}

class _AppUpdateSettingsPageState extends State<AppUpdateSettingsPage> {
  bool _autoCheck = AppUpdateService.autoCheckOnStartup;
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await AppUpdateService.getCurrentVersion();
    if (mounted) setState(() => _version = version);
  }

  Future<void> _setAutoCheck(bool value) async {
    setState(() => _autoCheck = value);
    await AppUpdateService.setAutoCheckOnStartup(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: 'Pengaturan Pembaruan',
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        actions: const [],
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            'Pembaruan',
            style: TextStyle(
              color: c.primaryLabel,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.separator.withValues(alpha: 0.45)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile.adaptive(
              value: _autoCheck,
              onChanged: _setAutoCheck,
              activeColor: const Color(0xFFF92D48),
              title: Text(
                'Periksa pembaruan saat startup',
                style: TextStyle(color: c.primaryLabel, fontSize: 16),
              ),
              subtitle: Text(
                'Otomatis memeriksa GitHub Release setelah aplikasi dibuka.',
                style: TextStyle(
                  color: c.secondaryLabel,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Informasi',
            style: TextStyle(
              color: c.primaryLabel,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.separator.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Versi saat ini',
                    style: TextStyle(color: c.secondaryLabel, fontSize: 14),
                  ),
                ),
                Text(
                  _version == null ? '—' : 'v$_version',
                  style: TextStyle(
                    color: c.primaryLabel,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
