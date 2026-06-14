part of '../radio_sections.dart';

class RadioStationsList extends StatelessWidget {
  const RadioStationsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        radioStations.length,
        (index) => RadioStationCard(station: radioStations[index]),
      ),
    );
  }
}
