
import 'package:flutter/cupertino.dart';
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
        toolbarHeight: 100,
      
      flexibleSpace: Padding(
  padding: const EdgeInsets.only(
    top: 45,
    right: 7,
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
    fontSize: 36,
  ),
),

     actions: [
Padding(
  padding: const EdgeInsets.only(
    right: 18,
    top: 12,
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
          margin: const EdgeInsets.only(left: 25, right: 10),
          child: Column(
            children: [

      Padding(
  padding: const EdgeInsets.only(
    left: 0,
    right: 0,
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
  CupertinoIcons.music_note_list,
  color: Color(0xFFF92D48),
  size: 28,
),
                          SizedBox(
                            width: 9,
                          ),
                          Text(
                            "Daftar Putar",
                            style: TextStyle(
                                color: Colors.white,
                                // fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                        ],
                      ),
                      
                    ],
                  ),
              const Divider(
  color: Color(0xFF38383A),
  thickness: 0.5,
  indent: 42,
  endIndent: 15,
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
  CupertinoIcons.mic,
  color: Color(0xFFF92D48),
  size: 30,
),
                          SizedBox(
                            width: 9,
                          ),
                          Text(
                            "Artis",
                            style: TextStyle(
                                color: Colors.white,
                                // fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                        ],
                      ),
                      
                    ],
                  ),
                  const Divider(
  color: Color(0xFF38383A),
  thickness: 0.5,
  indent: 42,
  endIndent: 15,
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
  CupertinoIcons.square_stack,
  color: Color(0xFFF92D48),
  size: 28,
),
                          SizedBox(
                            width: 9,
                          ),
                          Text(
                            "Album",
                            style: TextStyle(
                                color: Colors.white,
                                // fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                        ],
                      ),
                      
                    ],
                  ),
                  const Divider(
  color: Color(0xFF38383A),
  thickness: 0.5,
  indent: 42,
  endIndent: 15,
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
  CupertinoIcons.music_note,
  color: Color(0xFFF92D48),
  size: 30,
),
                            SizedBox(
                              width: 9,
                            ),
                            Text(
                              "Lagu",
                              style: TextStyle(
                                  color: Colors.white,
                                  // fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                          ],
                        ),
                        
                      ],
                    ),
                    const Divider(
  color: Color(0xFF38383A),
  thickness: 0.5,
  indent: 42,
  endIndent: 15,
                   ),               
                  ],
                ),
              ),
        Column(
  children: [
    Row(
      children: [
        Icon(
          CupertinoIcons.tv,
          color: Color(0xFFF92D48),
          size: 28,
        ),
        SizedBox(
          width: 9,
        ),
        Text(
          "TV & Film",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
          ),
        ),
      ],
    ),
    Divider(
      color: Color(0xFF38383A),
      thickness: 0.5,
      indent: 42,
      endIndent: 15,
    ),
  ],
),          
 ],
          ),
        ),
      ),
    );
  }
}
