package dev.wndavenz.music.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

data class GenreCategory(val name: String, val color: Color)

val genreCategories = listOf(
    GenreCategory("Pop", Color(0xFFE91E63)),
    GenreCategory("Rock", Color(0xFFF44336)),
    GenreCategory("Hip-Hop", Color(0xFF9C27B0)),
    GenreCategory("Electronic", Color(0xFF00BCD4)),
    GenreCategory("Indie", Color(0xFF4CAF50)),
    GenreCategory("Jazz", Color(0xFFFF9800)),
    GenreCategory("K-Pop", Color(0xFFE040FB)),
    GenreCategory("Acoustic", Color(0xFF8D6E63)),
)

@Composable
fun BrowseScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 16.dp)
    ) {
        Text(
            text = "Jelajahi Genre",
            style = MaterialTheme.typography.headlineMedium.copy(
                fontWeight = FontWeight.Bold,
                color = Color.White
            ),
            modifier = Modifier.padding(bottom = 16.dp)
        )

        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(bottom = 120.dp)
        ) {
            items(genreCategories) { genre ->
                Box(
                    modifier = Modifier
                        .height(100.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(genre.color)
                        .clickable { }
                        .padding(16.dp),
                    contentAlignment = Alignment.BottomStart
                ) {
                    Text(
                        text = genre.name,
                        style = MaterialTheme.typography.titleLarge.copy(
                            color = Color.White,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }
        }
    }
}
