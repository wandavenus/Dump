part of '../settings_page.dart';

class OpenSourceLicensePage extends StatelessWidget {
  const OpenSourceLicensePage({super.key});

  static const _licenses = <_ThirdPartyLicense>[
    _ThirdPartyLicense(
      name: 'Flutter',
      version: 'SDK',
      license: 'BSD 3-Clause',
      source: 'https://github.com/flutter/flutter',
      summary: 'Framework UI dan runtime aplikasi.',
    ),
    _ThirdPartyLicense(
      name: 'Dart',
      version: 'SDK',
      license: 'BSD 3-Clause',
      source: 'https://github.com/dart-lang/sdk',
      summary: 'Bahasa dan runtime untuk kode aplikasi.',
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'AndroidX Media3 (ExoPlayer)',
      version: '1.11.1',
      license: 'Apache License 2.0',
      source: 'https://github.com/androidx/media/tree/1.11.1',
      summary: 'Playback audio, ekstraksi media, dan sesi media Android.',
      licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
    ),
    _ThirdPartyLicense(
      name: 'Media3 FFmpeg decoder wrapper',
      version: '1.11.1',
      license: 'Apache License 2.0',
      source: 'https://github.com/androidx/media/tree/1.11.1/libraries/decoder_ffmpeg',
      summary: 'Wrapper JNI yang menghubungkan Media3 dengan decoder FFmpeg.',
      licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
    ),
    _ThirdPartyLicense(
      name: 'FFmpeg',
      version: '8.1.3',
      license: 'GNU LGPL 2.1 or later',
      source: 'https://github.com/FFmpeg/FFmpeg/tree/n8.1.3',
      summary: 'Library native untuk mendekode format audio tambahan. Build aplikasi mematikan komponen GPL dan nonfree.',
      licenseUrl: 'https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html',
      detailsAsset: 'android/decoder-ffmpeg/src/main/assets/licenses/COPYING.LGPLv2.1',
    ),
    _ThirdPartyLicense(
      name: 'libebur128',
      version: '1.2.6',
      license: 'MIT',
      source: 'https://github.com/jiixyj/libebur128/tree/v1.2.6',
      summary: 'Analisis loudness sesuai EBU R128 / ITU-R BS.1770.',
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'TagLib',
      version: '2.3',
      license: 'LGPL 2.1 or MPL 1.1',
      source: 'https://github.com/taglib/taglib/tree/v2.3',
      summary: 'Membaca dan menulis metadata tag audio. Tersedia di bawah LGPL 2.1 atau MPL 1.1.',
      licenseUrl: 'https://www.mozilla.org/en-US/MPL/1.1/',
    ),
    _ThirdPartyLicense(
      name: 'Signalsmith Stretch',
      version: '1.2.0',
      license: 'MIT',
      source: 'https://github.com/Signalsmith-Audio/signalsmith-stretch/tree/1.2.0',
      summary: 'Pemrosesan time-stretch dan pitch-shift audio.',
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'Signalsmith Linear',
      version: '0.1.2',
      license: 'MIT',
      source: 'https://github.com/Signalsmith-Audio/linear/tree/0.1.2',
      summary: 'Utilitas DSP dan FFT yang digunakan Signalsmith Stretch.',
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'AndroidX Palette',
      version: '1.1.0',
      license: 'Apache License 2.0',
      source: 'https://developer.android.com/jetpack/androidx/releases/palette',
      summary: 'Ekstraksi palet warna dari artwork.',
      licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
    ),
    _ThirdPartyLicense(
      name: 'audio_session',
      version: '0.2.4',
      license: 'MIT',
      source: 'https://pub.dev/packages/audio_session',
      summary: 'Konfigurasi sesi audio lintas platform.',
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'permission_handler',
      version: '12.0.3',
      license: 'MIT',
      source: 'https://pub.dev/packages/permission_handler',
      summary: 'Meminta dan memeriksa izin sistem.',
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'shared_preferences',
      version: '2.5.3',
      license: 'BSD 3-Clause',
      source: 'https://pub.dev/packages/shared_preferences',
      summary: 'Penyimpanan preferensi lokal.',
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'path_provider',
      version: '2.1.5',
      license: 'MIT',
      source: 'https://pub.dev/packages/path_provider',
      summary: 'Akses lokasi penyimpanan standar platform.',
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'url_launcher',
      version: '6.3.2',
      license: 'BSD 3-Clause',
      source: 'https://pub.dev/packages/url_launcher',
      summary: 'Membuka tautan menggunakan aplikasi platform.',
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'intl',
      version: '0.20.2',
      license: 'BSD 3-Clause',
      source: 'https://pub.dev/packages/intl',
      summary: 'Format tanggal, angka, dan dukungan lokalisasi.',
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'font_awesome_flutter',
      version: '11.0.0',
      license: 'MIT',
      source: 'https://pub.dev/packages/font_awesome_flutter',
      summary: 'Ikon Font Awesome untuk UI.',
      licenseUrl: 'https://opensource.org/license/mit',
    ),

  ];

  void _showLicense(BuildContext context, _ThirdPartyLicense license) {
    Navigator.of(context).push(
      ZoomFadeRoute<void>(
        page: _ThirdPartyLicenseDetailPage(license: license),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = context.l10n;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: l.openSourceLicense,
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
      body: ResponsivePageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                l.licensePageDescription,
                style: TextStyle(color: c.secondaryLabel, fontSize: 14, height: 1.5),
              ),
            ),
            const HeaderDivider(),
            for (final license in _licenses) ...[
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  license.name,
                  style: TextStyle(color: c.primaryLabel, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${license.license} · ${license.version}\n${license.summary}',
                    style: TextStyle(color: c.secondaryLabel, fontSize: 13, height: 1.4),
                  ),
                ),
                isThreeLine: true,
                trailing: Icon(CupertinoIcons.chevron_right, color: c.secondaryLabel, size: 17),
                onTap: () => _showLicense(context, license),
              ),
              const SettingsDivider(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThirdPartyLicense {
  final String name;
  final String version;
  final String license;
  final String source;
  final String summary;
  final String? licenseUrl;
  final String? detailsAsset;

  const _ThirdPartyLicense({
    required this.name,
    required this.version,
    required this.license,
    required this.source,
    required this.summary,
    this.licenseUrl,
    this.detailsAsset,
  });
}

class _ThirdPartyLicenseDetailPage extends StatelessWidget {
  const _ThirdPartyLicenseDetailPage({required this.license});

  final _ThirdPartyLicense license;

  Future<String>? get _bundledLicenseText => license.detailsAsset == null
      ? null
      : rootBundle.loadString(license.detailsAsset!);

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = context.l10n;
    final licenseText = _bundledLicenseText;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: license.name,
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
      body: ResponsivePageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Text(
              license.name,
              style: TextStyle(
                color: c.primaryLabel,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              license.license,
              style: TextStyle(
                color: c.primaryLabel,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${l.licenseVersion}: ${license.version}',
              style: TextStyle(color: c.secondaryLabel, fontSize: 14),
            ),
            const SizedBox(height: 16),
            const HeaderDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                license.summary,
                style: TextStyle(
                  color: c.primaryLabel,
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
            ),
            const HeaderDivider(),
            const SizedBox(height: 20),
            Text(
              l.licenseSource,
              style: TextStyle(
                color: c.primaryLabel,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              license.source,
              style: TextStyle(
                color: c.secondaryLabel,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openUrl(license.source),
              icon: const Icon(CupertinoIcons.link),
              label: Text(l.licenseSource),
            ),
            const SizedBox(height: 24),
            Text(
              l.licenseViewFullText,
              style: TextStyle(
                color: c.primaryLabel,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (licenseText != null)
              FutureBuilder<String>(
                future: licenseText,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Text(
                      l.licenseNoFullText,
                      style: TextStyle(
                        color: c.secondaryLabel,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    );
                  }
                  return SelectableText(
                    snapshot.data!,
                    style: TextStyle(
                      color: c.primaryLabel,
                      fontSize: 12,
                      height: 1.5,
                      fontFamily: 'monospace',
                    ),
                  );
                },
              )
            else
              Text(
                l.licenseNoFullText,
                style: TextStyle(
                  color: c.secondaryLabel,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            if (license.licenseUrl != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: () => _openUrl(license.licenseUrl!),
                  child: Text(l.licenseViewFullText),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

