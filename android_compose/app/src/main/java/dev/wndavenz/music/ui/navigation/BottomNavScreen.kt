package dev.wndavenz.music.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import dev.wndavenz.music.models.LocalSong
import dev.wndavenz.music.models.Playlist
import dev.wndavenz.music.ui.components.FullPlayerSheet
import dev.wndavenz.music.ui.components.MiniPlayerBar
import dev.wndavenz.music.ui.screens.*

sealed class NavTab(val title: String, val icon: ImageVector) {
    object Home : NavTab("Dengarkan", Icons.Default.Home)
    object Browse : NavTab("Jelajahi", Icons.Default.GridView)
    object Radio : NavTab("Radio", Icons.Default.Sensors)
    object Library : NavTab("Perpustakaan", Icons.Default.Subscriptions)
    object Search : NavTab("Cari", Icons.Default.Search)
}

@Composable
fun BottomNavScreen(
    songs: List<LocalSong>,
    playlists: List<Playlist>,
    currentSong: LocalSong?,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    onSongSelect: (LocalSong) -> Unit,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onSeek: (Long) -> Unit,
    onCreatePlaylist: (String) -> Unit,
) {
    var selectedTab by remember { mutableStateOf<NavTab>(NavTab.Home) }
    var showFullPlayer by remember { mutableStateOf(false) }
    var currentSubScreen by remember { mutableStateOf<String?>(null) }

    val tabs = listOf(
        NavTab.Home,
        NavTab.Browse,
        NavTab.Radio,
        NavTab.Library,
        NavTab.Search
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f)) {
                when (currentSubScreen) {
                    "settings" -> SettingsScreen(
                        onBack = { currentSubScreen = null },
                        onEqualizerClick = { currentSubScreen = "equalizer" },
                        onSleepTimerClick = {}
                    )
                    "equalizer" -> EqualizerScreen(
                        onBack = { currentSubScreen = "settings" }
                    )
                    else -> when (selectedTab) {
                        NavTab.Home -> HomeScreen(
                            songs = songs,
                            onSongSelect = onSongSelect,
                            onPlayAll = { if (songs.isNotEmpty()) onSongSelect(songs.first()) },
                            onSettingsClick = { currentSubScreen = "settings" }
                        )
                        NavTab.Browse -> BrowseScreen()
                        NavTab.Radio -> RadioScreen()
                        NavTab.Library -> LibraryScreen(
                            playlists = playlists,
                            onCreatePlaylist = onCreatePlaylist,
                            onPlaylistSelect = {}
                        )
                        NavTab.Search -> SearchScreen(
                            songs = songs,
                            onSongSelect = onSongSelect
                        )
                    }
                }
            }
        }

        // Floating Pill Mini Player & Bottom Nav Bar overlay
        if (currentSubScreen == null) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                if (currentSong != null && !showFullPlayer) {
                    MiniPlayerBar(
                        currentSong = currentSong,
                        isPlaying = isPlaying,
                        onPlayPause = onPlayPause,
                        onNext = onNext,
                        onClick = { showFullPlayer = true },
                        modifier = Modifier.padding(bottom = 8.dp)
                    )
                }

                // Glass Pill Navigation Bar
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(60.dp)
                        .clip(RoundedCornerShape(30.dp))
                        .background(Color(0xCC1C1C1E))
                ) {
                    Row(
                        modifier = Modifier.fillMaxSize(),
                        horizontalArrangement = Arrangement.SpaceAround,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        tabs.forEach { tab ->
                            val isSelected = selectedTab == tab
                            IconButton(onClick = { selectedTab = tab }) {
                                Icon(
                                    imageVector = tab.icon,
                                    contentDescription = tab.title,
                                    tint = if (isSelected) MaterialTheme.colorScheme.primary else Color.Gray
                                )
                            }
                        }
                    }
                }
            }
        }

        // Full Player Modal Sheet
        if (showFullPlayer && currentSong != null) {
            FullPlayerSheet(
                song = currentSong,
                isPlaying = isPlaying,
                positionMs = positionMs,
                durationMs = durationMs,
                onPlayPause = onPlayPause,
                onNext = onNext,
                onPrevious = onPrevious,
                onSeek = onSeek,
                onClose = { showFullPlayer = false }
            )
        }
    }
}
