part of '../radio_sections.dart';

class RadioPageContent extends StatelessWidget {
  const RadioPageContent({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomClearance = navBottomClearance(context);
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LargePageTitle(title: context.l10n.navRadio),
          const HeaderDivider(),
          const SizedBox(height: 12),
          const _SmartPlaylistCardWidget(index: 0),
          const _UserPlaylistsSection(),
        ],
      ),
    );
  }
}
