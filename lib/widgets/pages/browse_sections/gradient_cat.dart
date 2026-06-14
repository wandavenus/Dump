part of '../browse_sections.dart';

class _GradientCategory extends StatelessWidget {
  const _GradientCategory({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [
                Color.fromARGB(255, 251, 47, 88),
                Color.fromARGB(255, 255, 174, 174),
              ],
              stops: [0.4, 1],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          margin: const EdgeInsets.only(top: 10, left: 10),
          height: 100,
          width: 200,
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 15),
                ],
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 5, left: 10),
          child: Text(subtitle, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
