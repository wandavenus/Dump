part of '../radio_sections.dart';

class RadioPageContent extends StatelessWidget {
  const RadioPageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LargePageTitle(title: 'Radio'),
          HeaderDivider(),
          SizedBox(height: 12),
          _SmartPlaylistCardWidget(index: 0),
          _SmartPlaylistCardWidget(index: 1),
          _SmartPlaylistCardWidget(index: 2),
          _UserPlaylistsSection(),
          SizedBox(height: 8),
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
