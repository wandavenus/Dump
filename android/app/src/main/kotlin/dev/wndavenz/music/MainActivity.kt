package dev.wndavenz.music

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.Equalizer
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Radio
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

class MainActivity : ComponentActivity() {
    private val viewModel: MusicAppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setRecentTaskLabel()
        viewModel.acceptOpenUri(extractAudioUri(intent))
        setContent { MusicComposeApp(viewModel) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        viewModel.acceptOpenUri(extractAudioUri(intent))
    }

    private fun setRecentTaskLabel() {
        val label = getString(R.string.app_name)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setTaskDescription(ActivityManager.TaskDescription.Builder().setLabel(label).build())
        } else {
            @Suppress("DEPRECATION")
            setTaskDescription(ActivityManager.TaskDescription(label))
        }
    }

    private fun extractAudioUri(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri: Uri = intent.data ?: return null
        val scheme = uri.scheme.orEmpty()
        val mimeType = intent.type ?: contentResolver.getType(uri).orEmpty()
        return when {
            mimeType.startsWith("audio/") -> uri.toString()
            scheme == "content" -> null
            scheme == "file" || scheme.isEmpty() -> {
                val ext = uri.lastPathSegment?.substringAfterLast('.')?.lowercase().orEmpty()
                if (ext in AUDIO_EXTENSIONS) uri.toString() else null
            }
            else -> null
        }
    }

    private companion object {
        val AUDIO_EXTENSIONS = setOf("mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "aiff", "aif", "wma", "alac", "ape", "dsf", "dff", "mka", "webm")
    }
}

data class MusicUiState(
    val selectedTab: AppTab = AppTab.Home,
    val isPlaying: Boolean = false,
    val currentTrack: String = "No song playing",
    val currentArtist: String = "Select a track to start playback",
    val progress: Float = 0f,
    val openUri: String? = null,
)

class MusicAppViewModel : ViewModel() {
    private val _state = MutableStateFlow(MusicUiState())
    val state: StateFlow<MusicUiState> = _state

    fun selectTab(tab: AppTab) = _state.update { it.copy(selectedTab = tab) }
    fun togglePlayback() = _state.update { it.copy(isPlaying = !it.isPlaying) }
    fun seek(progress: Float) = _state.update { it.copy(progress = progress) }
    fun acceptOpenUri(uri: String?) {
        if (uri != null) _state.update { it.copy(openUri = uri, currentTrack = uri.substringAfterLast('/'), currentArtist = "Opened from file", selectedTab = AppTab.Home) }
    }
}

enum class AppTab(val label: String, val icon: ImageVector) {
    Home("Home", Icons.Filled.Home),
    Library("Library", Icons.Filled.LibraryMusic),
    Browse("Browse", Icons.Filled.Folder),
    Radio("Radio", Icons.Filled.Radio),
    Settings("Settings", Icons.Filled.Settings),
}

private val appScheme = darkColorScheme(
    background = Color(0xFF0B0B12),
    surface = Color(0xFF151521),
    surfaceVariant = Color(0xFF202030),
    primary = Color(0xFF8E7CFF),
    secondary = Color(0xFF64D2FF),
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable
fun MusicComposeApp(viewModel: MusicAppViewModel) {
    val state by viewModel.state.collectAsState()
    MaterialTheme(colorScheme = appScheme) {
        Surface(Modifier.fillMaxSize()) {
            Scaffold(
                containerColor = MaterialTheme.colorScheme.background,
                topBar = { MusicTopBar(state.selectedTab.label) },
                bottomBar = {
                    Column {
                        MiniPlayer(state, viewModel::togglePlayback, viewModel::seek)
                        BottomTabs(state.selectedTab, viewModel::selectTab)
                    }
                },
            ) { padding ->
                AppContent(state, Modifier.padding(padding))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MusicTopBar(title: String) {
    TopAppBar(title = { Text(title, fontWeight = FontWeight.SemiBold) }, actions = { IconButton({}) { Icon(Icons.Filled.Search, null) } })
}

@Composable
private fun AppContent(state: MusicUiState, modifier: Modifier = Modifier) {
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { HeroCard(state) }
        val rows = when (state.selectedTab) {
            AppTab.Home -> listOf("Recently played", "Albums", "Artists", "Most played", "Playlists")
            AppTab.Library -> listOf("Songs", "Albums", "Artists", "Playlists", "Folders")
            AppTab.Browse -> listOf("Device storage", "Audio folders", "Recently added", "File scanner")
            AppTab.Radio -> listOf("Favorite stations", "Local radio", "Online radio", "Recently streamed")
            AppTab.Settings -> listOf("Audio", "Equalizer", "Playback engine", "Appearance", "Language", "Debug", "About")
        }
        items(rows) { row -> FeatureRow(row) }
    }
}

@Composable
private fun HeroCard(state: MusicUiState) {
    Card(colors = CardDefaults.cardColors(containerColor = Color.Transparent), shape = RoundedCornerShape(28.dp)) {
        Box(Modifier.background(Brush.linearGradient(listOf(Color(0xFF5B4BCE), Color(0xFF10101A)))).fillMaxWidth().padding(22.dp)) {
            Column { Text("Dump Music", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold); Spacer(Modifier.height(8.dp)); Text(state.currentTrack, maxLines = 1, overflow = TextOverflow.Ellipsis); Text(state.currentArtist, color = Color.White.copy(alpha = .72f), maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@Composable
private fun FeatureRow(label: String) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.surface).clickable { }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(iconFor(label), null, tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(16.dp))
        Text(label, style = MaterialTheme.typography.titleMedium)
    }
}

private fun iconFor(label: String): ImageVector = when {
    label.contains("Album", true) -> Icons.Filled.Album
    label.contains("Artist", true) -> Icons.Filled.Person
    label.contains("Playlist", true) -> Icons.AutoMirrored.Filled.PlaylistPlay
    label.contains("Equalizer", true) -> Icons.Filled.Equalizer
    label.contains("Debug", true) -> Icons.AutoMirrored.Filled.Article
    else -> Icons.Filled.MusicNote
}

@Composable
private fun MiniPlayer(state: MusicUiState, onPlayPause: () -> Unit, onSeek: (Float) -> Unit) {
    val alpha by animateFloatAsState(if (state.isPlaying) 1f else .86f, label = "miniPlayerAlpha")
    Card(Modifier.padding(horizontal = 12.dp).alpha(alpha), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant), shape = RoundedCornerShape(24.dp)) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) { Icon(Icons.Filled.MusicNote, null) }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) { Text(state.currentTrack, maxLines = 1, overflow = TextOverflow.Ellipsis); Text(state.currentArtist, color = Color.White.copy(alpha = .65f), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                IconButton({}) { Icon(Icons.Filled.SkipPrevious, null) }
                IconButton(onPlayPause) { Icon(if (state.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, null) }
                IconButton({}) { Icon(Icons.Filled.SkipNext, null) }
            }
            Slider(value = state.progress, onValueChange = onSeek)
        }
    }
}

@Composable
private fun BottomTabs(selected: AppTab, onSelect: (AppTab) -> Unit) {
    NavigationBar(windowInsets = WindowInsets.navigationBars) {
        AppTab.entries.forEach { tab -> NavigationBarItem(selected = selected == tab, onClick = { onSelect(tab) }, icon = { Icon(tab.icon, null) }, label = { Text(tab.label) }) }
    }
}
