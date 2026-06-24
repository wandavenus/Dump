part of '../radio_sections.dart';

class RadioPageContent extends StatelessWidget {
  const RadioPageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Column(
        children: [
          LargePageTitle(title: 'Radio'),
          HeaderDivider(),
          SizedBox(height: 12),
          RadioStationsList(),
          SectionTitle(
            title: 'Recently Played',
            routeName: '/musiclist',
            horizontalPadding: 16,
            showChevron: false,
          ),
          _RecentlyPlayedSection(),
        ],
      ),
    );
  }
}

// ─── Radio stations (konten statis — tidak berubah) ───────────────────────────
