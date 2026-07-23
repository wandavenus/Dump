part of '../artist_list_sections.dart';

class ArtistListContent extends StatefulWidget {
  final ScrollController? scrollController;

  const ArtistListContent({super.key, this.scrollController});

  @override
  State<ArtistListContent> createState() => _ArtistListContentState();
}
