part of '../search_sections.dart';

class SearchSlivers extends StatefulWidget {
  const SearchSlivers({super.key, required this.scrollOffset});

  final double scrollOffset;

  @override
  State<SearchSlivers> createState() => _SearchSliversState();
}
