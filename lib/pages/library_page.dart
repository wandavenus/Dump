
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
        toolbarHeight: 125,
      
       flexibleSpace: Stack(
  children: [

    

    Positioned(
      left: 16,
      top: 110,
      child: Text(
        "Perpustakaan",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 34,
          color: Colors.white,
        ),
      ),
    ),

    Positioned(
      right: 18,
      top: 130,
      child: Text(
        "Edit",
        style: TextStyle(
          color: Color(0xFFF92D48),
          fontSize: 17,
        ),
      ),
    ),
  ],
),      
      ),
      body: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [

      Padding(
  padding: const EdgeInsets.only(
    left: 0,
    right: 0,
  ),
  child: const Divider(
    color: Color(0xFF38383A),
    thickness: 0.5,
    height: 16,
  ),
),
             const Column(
               children: [
   padding: const EdgeInsets.symmetric(
    vertical: 6,              
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
  indent: 38,
  endIndent: 8,
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
  size: 28,
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
  indent: 38,
  endIndent: 8,
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
  indent: 38,
  endIndent: 8,
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
  size: 28,
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
  indent: 38,
  endIndent: 8,
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
      indent: 38,
      endIndent: 8,
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
