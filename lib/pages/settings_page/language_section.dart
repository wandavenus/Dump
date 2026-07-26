part of '../settings_page.dart';

// ─── Language Section ─────────────────────────────────────────────────────────

class _LanguageSection extends StatefulWidget {
  const _LanguageSection();

  @override
  State<_LanguageSection> createState() => _LanguageSectionState();
}

class _LanguageSectionState extends State<_LanguageSection> {
  String _currentCode = 'system';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final code = await LanguageManager.instance.getSavedCode();
    if (mounted) setState(() => _currentCode = code);
  }

  String _codeLabel(BuildContext context, String code) {
    final l = context.l10n;
    return switch (code) {
      'en' => l.languageEnglish,
      'id' => l.languageIndonesian,
      _ => l.languageSystem,
    };
  }

  Future<void> _showPicker(BuildContext context) async {
    final l = context.l10n;
    final c = AppColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SwipeToDismissSheet(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.dragHandle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l.languageTitle,
                    style: TextStyle(
                      color: c.primaryLabel,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _LanguageOption(
                label: l.languageSystem,
                code: 'system',
                selected: _currentCode == 'system',
                onTap: _select,
              ),
              Divider(height: 1, thickness: 0.5, color: c.separator, indent: 52),
              _LanguageOption(
                label: l.languageEnglish,
                code: 'en',
                selected: _currentCode == 'en',
                onTap: _select,
              ),
              Divider(height: 1, thickness: 0.5, color: c.separator, indent: 52),
              _LanguageOption(
                label: l.languageIndonesian,
                code: 'id',
                selected: _currentCode == 'id',
                onTap: _select,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _select(String code) async {
    Navigator.pop(context);
    await LanguageManager.instance.setLanguage(code);
    if (mounted) setState(() => _currentCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.sectionLanguage),
        const SizedBox(height: 6),
        SettingsActionRow(
          title: l.languageTitle,
          subtitle: _codeLabel(context, _currentCode),
          onTap: () => _showPicker(context),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String label;
  final String code;
  final bool selected;
  final void Function(String) onTap;

  const _LanguageOption({
    required this.label,
    required this.code,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: () => onTap(code),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: c.primaryLabel, fontSize: 16),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, color: const Color(0xFFF92D48), size: 20),
          ],
        ),
      ),
    );
  }
}
