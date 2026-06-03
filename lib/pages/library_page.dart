
import 'package:flutter/material.dart';
// import 'package:icons_flutter/icons_flutter.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 145,
      
      flexibleSpace: Padding(
  padding: const EdgeInsets.only(
    top: 65,
    right: 18,
  ),
  child: Align(
    alignment: Alignment.topRight,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cast_outlined,
          color: Color(0xFFF92D48),
          size: 24,
        ),
        SizedBox(width: 16),
        PopupMenuButton(
  icon: const Icon(
    Icons.more_vert,
    color: Color(0xFFF92D48),
    size: 24,
  ),
  itemBuilder: (context) => [
    const PopupMenuItem(
      value: 'settings',
      child: Text('Pengaturan'),
    ),
  ],
),
      ],
    ),
  ),
),
      
  title: const Text(
  "Perpustakaan",
  style: TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 38,
  ),
),

     actions: [
Padding(
  padding: const EdgeInsets.only(
    right: 18,
    top: 8,
  ),
    child: Center(
      child: Text(
        'Edit',
        style: TextStyle(
          color: Color(0xFFF92D48),
          fontSize: 18,
        ),
      ),
    ),
  ),
],
      ),
      body: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.only(left: 18, right: 10),
          child: Column(
            children: [

      Padding(
  padding: const EdgeInsets.only(
    left: 7,
    right: 15,
  ),
  child: const Divider(
    color: Color(0xFF2C2C2E),
    thickness: 0.5,
    height: 1,
  ),
),
             const Column(
               children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            color: Color(0xFFF92D48),
                            size: 30,
                          ),
                          SizedBox(
                            width: 12,
                          ),
                          Text(
                            "Daftar Putar",
                            style: TextStyle(
                                color: Colors.white,
                                // fontWeight: FontWeight.bold,
                                fontSize: 20),
                          ),
                        ],
                      ),
                      
                    ],
                  ),
              const Divider(
  color: Color(0xFF38383A),
  thickness: 0.5,
  indent: 68,
  endIndent: 18,
),
                ],
              ),
              const Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.mic_external_on,
                            color: Color(0xFFF92D48),
                            size: 30,
                          ),
                          SizedBox(
                            width: 10,
                          ),
                          Text(
                            "Artis",
                            style: TextStyle(
                                color: Colors.white,
                                // fontWeight: FontWeight.bold,
                                fontSize: 20),
                          ),
                        ],
                      ),
                      
                    ],
                  ),
                  const Divider(
  color: Color(0xFF38383A),
  thickness: 0.5,
  indent: 68,
  endIndent: 18,
),
                ],
              ),
              const Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.subscriptions_rounded,
                            color: Color(0xFFF92D48),
                            size: 30,
                          ),
                          SizedBox(
                            width: 10,
                          ),
                          Text(
                            "Album",
                            style: TextStyle(
                                color: Colors.white,
                                // fontWeight: FontWeight.bold,
                                fontSize: 20),
                          ),
                        ],
                      ),
                      
                    ],
                  ),
                  const Divider(
  color: Color(0xFF38383A),
  thickness: 0.5,
  indent: 68,
  endIndent: 18,
),
                ],
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, "/musiclist");
                },
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.music_note,
                              color: Color(0xFFF92D48),
                              size: 30,
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            Text(
                              "Lagu",
                              style: TextStyle(
                                  color: Colors.white,
                                  // fontWeight: FontWeight.bold,
                                  fontSize: 20),
                            ),
                          ],
                        ),
                        
                      ],
                    ),
                    const Divider(
  color: Color(0xFF38383A),
  thickness: 0.5,
  indent: 68,
  endIndent: 18,
                   ),               
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
