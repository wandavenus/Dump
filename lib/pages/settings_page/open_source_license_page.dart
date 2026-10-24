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
      licenseDocuments: [
        _LicenseDocument(label: 'BSD 3-Clause License', assetPath: 'assets/licenses/flutter-BSD-3-Clause.txt'),
      ],
    ),
    _ThirdPartyLicense(
      name: 'Dart',
      version: 'SDK',
      license: 'BSD 3-Clause',
      source: 'https://github.com/dart-lang/sdk',
      summary: 'Bahasa dan runtime untuk kode aplikasi.',
      licenseDocuments: [
        _LicenseDocument(label: 'BSD 3-Clause License', assetPath: 'assets/licenses/dart-BSD-3-Clause.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'AndroidX Media3 (ExoPlayer)',
      version: '1.11.1',
      license: 'Apache License 2.0',
      source: 'https://github.com/androidx/media/tree/1.11.1',
      summary: 'Playback audio, ekstraksi media, dan sesi media Android.',
      licenseDocuments: [
        _LicenseDocument(label: 'Apache License 2.0', assetPath: 'assets/licenses/Apache-2.0.txt'),
      ],
      licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
    ),
    _ThirdPartyLicense(
      name: 'Media3 FFmpeg decoder wrapper',
      version: '1.11.1',
      license: 'Apache License 2.0',
      source: 'https://github.com/androidx/media/tree/1.11.1/libraries/decoder_ffmpeg',
      summary: 'Wrapper JNI yang menghubungkan Media3 dengan decoder FFmpeg.',
      licenseDocuments: [
        _LicenseDocument(label: 'Apache License 2.0', assetPath: 'assets/licenses/Apache-2.0.txt'),
      ],
      licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
    ),
    _ThirdPartyLicense(
      name: 'FFmpeg',
      version: '8.1.3',
      license: 'GNU LGPL 2.1 or later',
      source: 'https://github.com/FFmpeg/FFmpeg/tree/n8.1.3',
      summary: 'Library native untuk mendekode format audio tambahan. Build aplikasi mematikan komponen GPL dan nonfree.',
      licenseDocuments: [
        _LicenseDocument(label: 'GNU Lesser General Public License 2.1', assetPath: 'assets/licenses/ffmpeg-LGPL-2.1.txt'),
      ],
      licenseUrl: 'https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html',
    ),
    _ThirdPartyLicense(
      name: 'libebur128',
      version: '1.2.6',
      license: 'MIT',
      source: 'https://github.com/jiixyj/libebur128/tree/v1.2.6',
      summary: 'Analisis loudness sesuai EBU R128 / ITU-R BS.1770.',
      licenseDocuments: [
        _LicenseDocument(label: 'MIT License', assetPath: 'assets/licenses/libebur128-MIT.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'TagLib',
      version: '2.3',
      license: 'LGPL 2.1 or MPL 1.1',
      source: 'https://github.com/taglib/taglib/tree/v2.3',
      summary: 'Membaca dan menulis metadata tag audio. Tersedia di bawah LGPL 2.1 atau MPL 1.1.',
      licenseDocuments: [
        _LicenseDocument(label: 'GNU Lesser General Public License 2.1', assetPath: 'assets/licenses/taglib-LGPL-2.1.txt'),
        _LicenseDocument(label: 'Mozilla Public License 1.1', assetPath: 'assets/licenses/taglib-MPL-1.1.txt'),
      ],
      licenseUrl: 'https://www.mozilla.org/en-US/MPL/1.1/',
    ),
    _ThirdPartyLicense(
      name: 'Signalsmith Stretch',
      version: '1.2.0',
      license: 'MIT',
      source: 'https://github.com/Signalsmith-Audio/signalsmith-stretch/tree/1.2.0',
      summary: 'Pemrosesan time-stretch dan pitch-shift audio.',
      licenseDocuments: [
        _LicenseDocument(label: 'MIT License', assetPath: 'assets/licenses/signalsmith-stretch-MIT.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'Signalsmith Linear',
      version: '0.1.2',
      license: 'MIT',
      source: 'https://github.com/Signalsmith-Audio/linear/tree/0.1.2',
      summary: 'Utilitas DSP dan FFT yang digunakan Signalsmith Stretch.',
      licenseDocuments: [
        _LicenseDocument(label: 'MIT License', assetPath: 'assets/licenses/signalsmith-linear-MIT.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'AndroidX Palette',
      version: '1.1.0',
      license: 'Apache License 2.0',
      source: 'https://developer.android.com/jetpack/androidx/releases/palette',
      summary: 'Ekstraksi palet warna dari artwork.',
      licenseDocuments: [
        _LicenseDocument(label: 'Apache License 2.0', assetPath: 'assets/licenses/Apache-2.0.txt'),
      ],
      licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
    ),
    _ThirdPartyLicense(
      name: 'audio_session',
      version: '0.2.4',
      license: 'MIT',
      source: 'https://pub.dev/packages/audio_session',
      summary: 'Konfigurasi sesi audio lintas platform.',
      licenseDocuments: [
        _LicenseDocument(label: 'MIT License', assetPath: 'assets/licenses/audio-session-MIT.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'permission_handler',
      version: '12.0.3',
      license: 'MIT',
      source: 'https://pub.dev/packages/permission_handler',
      summary: 'Meminta dan memeriksa izin sistem.',
      licenseDocuments: [
        _LicenseDocument(label: 'MIT License', assetPath: 'assets/licenses/permission-handler-MIT.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/mit',
    ),
    _ThirdPartyLicense(
      name: 'shared_preferences',
      version: '2.5.3',
      license: 'BSD 3-Clause',
      source: 'https://pub.dev/packages/shared_preferences',
      summary: 'Penyimpanan preferensi lokal.',
      licenseDocuments: [
        _LicenseDocument(label: 'BSD 3-Clause License', assetPath: 'assets/licenses/flutter-packages-BSD-3-Clause.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'path_provider',
      version: '2.1.5',
      license: 'BSD 3-Clause',
      source: 'https://pub.dev/packages/path_provider',
      summary: 'Akses lokasi penyimpanan standar platform.',
      licenseDocuments: [
        _LicenseDocument(label: 'BSD 3-Clause License', assetPath: 'assets/licenses/flutter-packages-BSD-3-Clause.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'url_launcher',
      version: '6.3.2',
      license: 'BSD 3-Clause',
      source: 'https://pub.dev/packages/url_launcher',
      summary: 'Membuka tautan menggunakan aplikasi platform.',
      licenseDocuments: [
        _LicenseDocument(label: 'BSD 3-Clause License', assetPath: 'assets/licenses/flutter-packages-BSD-3-Clause.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'intl',
      version: '0.20.2',
      license: 'BSD 3-Clause',
      source: 'https://pub.dev/packages/intl',
      summary: 'Format tanggal, angka, dan dukungan lokalisasi.',
      licenseDocuments: [
        _LicenseDocument(label: 'BSD 3-Clause License', assetPath: 'assets/licenses/intl-BSD-3-Clause.txt'),
      ],
      licenseUrl: 'https://opensource.org/license/bsd-3-clause',
    ),
    _ThirdPartyLicense(
      name: 'font_awesome_flutter',
      version: '11.0.0',
      license: 'MIT · CC BY 4.0 · SIL OFL 1.1',
      source: 'https://pub.dev/packages/font_awesome_flutter',
      summary: 'Kode paket berlisensi MIT; ikon Font Awesome berlisensi CC BY 4.0 dan font-nya SIL OFL 1.1.',
      licenseDocuments: [
        _LicenseDocument(label: 'MIT License (package code)', assetPath: 'assets/licenses/font-awesome-flutter-MIT.txt'),
        _LicenseDocument(label: 'Creative Commons Attribution 4.0 International (icons)', assetPath: 'assets/licenses/font-awesome-CC-BY-4.0.txt'),
        _LicenseDocument(label: 'SIL Open Font License 1.1 (fonts)', assetPath: 'assets/licenses/font-awesome-OFL-1.1.txt'),
      ],
      licenseUrl: 'https://fontawesome.com/license/free',
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
  final List<_LicenseDocument> licenseDocuments;

  const _ThirdPartyLicense({
    required this.name,
    required this.version,
    required this.license,
    required this.source,
    required this.summary,
    this.licenseUrl,
    this.licenseDocuments = const [],
  });
}

class _LicenseDocument {
  const _LicenseDocument({required this.label, required this.assetPath});

  final String label;
  final String assetPath;
}

class _ThirdPartyLicenseDetailPage extends StatelessWidget {
  const _ThirdPartyLicenseDetailPage({required this.license});

  final _ThirdPartyLicense license;

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
            if (license.licenseDocuments.isEmpty)
              Text(
                l.licenseNoFullText,
                style: TextStyle(
                  color: c.secondaryLabel,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            for (final document in license.licenseDocuments) ...[
              Text(
                document.label,
                style: TextStyle(
                  color: c.primaryLabel,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: rootBundle.loadString(document.assetPath),
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
              ),
              const SizedBox(height: 20),
            ],
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

