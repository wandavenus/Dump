part of '../browse_sections.dart';

class BrowseCategoryStrip extends StatelessWidget {
  const BrowseCategoryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 145,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: const [
          _GradientCategory(title: 'Music', subtitle: 'Start Singing'),
          _GradientCategory(title: 'Hits', subtitle: 'Listen Now'),
          _GradientCategory(title: 'Pop', subtitle: 'Explore More'),
        ],
      ),
    );
  }
}
