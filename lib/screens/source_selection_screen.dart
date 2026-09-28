import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/watchlist_button.dart';
import 'episode_list_screen.dart';

class SourceSelectionScreen extends StatefulWidget {
  final String animeTitle;
  final String imageUrl;
  final String myAnimeListUrl;

  const SourceSelectionScreen({
    super.key,
    required this.animeTitle,
    required this.imageUrl,
    required this.myAnimeListUrl,
  });

  @override
  State<SourceSelectionScreen> createState() => _SourceSelectionScreenState();
}

class _SourceSelectionScreenState extends State<SourceSelectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  bool _isSearchingSources = false;
  List<Anime> _aniDBResults = [];
  List<Anime> _animeFireResults = [];
  List<Anime> _goyabuResults = [];
  String? _searchErrorMessage;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();
    _searchSources();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _searchSources() async {
    setState(() {
      _isSearchingSources = true;
      _searchErrorMessage = null;
    });

    try {
      final results = await AnimeService.searchAnime(widget.animeTitle);
      if (!mounted) return;
      setState(() {
        _aniDBResults = results
            .where((anime) => anime.source == AnimeSource.aniDb)
            .toList();
        _animeFireResults = results
            .where((anime) => anime.source == AnimeSource.animeFire)
            .toList();
        _goyabuResults = results
            .where((anime) => anime.source == AnimeSource.goyabu)
            .toList();
        _isSearchingSources = false;
      });
    } catch (e) {
      debugPrint('Error searching anime sources: $e');
      if (!mounted) return;
      setState(() {
        _isSearchingSources = false;
        _searchErrorMessage =
            'Could not search anime sources. Check your connection and retry.';
      });
    }
  }

  Future<void> _selectSource(AnimeSource source) async {
    final results = switch (source) {
      AnimeSource.aniDb => _aniDBResults,
      AnimeSource.animeFire => _animeFireResults,
      AnimeSource.goyabu => _goyabuResults,
    };
    if (results.isEmpty) return;

    final selected = results.length == 1
        ? results.first
        : await _showVersionSelectionDialog(results);
    if (selected == null || !mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ModernEpisodeListScreen(anime: selected),
      ),
    );
  }

  void _openSourceWebsite(String sourceName, Uri uri) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SourceWebViewScreen(initialUrl: uri.toString(), title: sourceName),
      ),
    );
  }

  void _openAniDBWebsite() {
    _openSourceWebsite(
      'AniDB',
      Uri.https('anidb.app', '/browse', {'q': widget.animeTitle}),
    );
  }

  void _openAnimeFireWebsite() {
    final query = widget.animeTitle.toLowerCase().trim().replaceAll(' ', '-');
    _openSourceWebsite(
      'AnimeFire',
      Uri.https('animefire.io', '/pesquisar/$query'),
    );
  }

  void _openGoyabuWebsite() {
    _openSourceWebsite(
      'Goyabu',
      Uri.https('goyabu.io', '/', {'s': widget.animeTitle}),
    );
  }

  void _openSuperFlixWebsite() {
    _openSourceWebsite(
      'SuperFlix',
      Uri.https('superflixapi.monster', '/pesquisar', {'s': widget.animeTitle}),
    );
  }

  Future<Anime?> _showVersionSelectionDialog(List<Anime> results) async {
    final l10n = AppLocalizations.of(context);

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.backgroundLight,
          title: Text(
            l10n.locale.languageCode == 'pt'
                ? 'Selecione a versão'
                : 'Select Version',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (context, index) {
                final anime = results[index];
                return ListTile(
                  title: Text(
                    anime.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    anime.sourceName,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    color: AppColors.primary,
                  ),
                  onTap: () => Navigator.pop(context, anime),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                l10n.locale.languageCode == 'pt' ? 'Cancelar' : 'Cancel',
                style: const TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // AppBar com imagem do anime
          SliverAppBar(
            expandedHeight: 300,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                l10n.selectVersion,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 2),
                      blurRadius: 8,
                      color: Colors.black87,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: AppColors.surface),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.surface,
                      child: const Icon(Icons.error, color: Colors.white54),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.background.withValues(alpha: 0.8),
                          AppColors.background,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Conteúdo
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Título do anime com botão de watchlist
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          widget.animeTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      WatchlistButton(
                        animeId: widget.myAnimeListUrl,
                        title: widget.animeTitle,
                        coverImage: widget.imageUrl,
                        myAnimeListUrl: widget.myAnimeListUrl,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.selectVersion,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // AniDB provides English and Japanese audio tracks.
                  _buildSourceCard(
                    title: 'AniDB',
                    subtitle: _isSearchingSources
                        ? l10n.searching
                        : _aniDBResults.isNotEmpty
                        ? 'Available • ${_aniDBResults.length} results • Japanese / English'
                        : 'Browse AniDB directly',
                    icon: Icons.public,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    available: !_isSearchingSources,
                    isLoading: _isSearchingSources,
                    onTap: _aniDBResults.isNotEmpty
                        ? () => _selectSource(AnimeSource.aniDb)
                        : _openAniDBWebsite,
                  ),

                  const SizedBox(height: 16),

                  // Opção AnimeFire
                  _buildSourceCard(
                    title: 'AnimeFire',
                    subtitle: _isSearchingSources
                        ? l10n.searching
                        : _animeFireResults.isNotEmpty
                        ? 'Available • ${_animeFireResults.length} results • PT-BR'
                        : 'Browse AnimeFire directly',
                    icon: Icons.local_fire_department,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
                    ),
                    available: !_isSearchingSources,
                    isLoading: _isSearchingSources,
                    onTap: _animeFireResults.isNotEmpty
                        ? () => _selectSource(AnimeSource.animeFire)
                        : _openAnimeFireWebsite,
                  ),

                  const SizedBox(height: 16),

                  _buildSourceCard(
                    title: 'Goyabu',
                    subtitle: _isSearchingSources
                        ? l10n.searching
                        : _goyabuResults.isNotEmpty
                        ? 'Available • ${_goyabuResults.length} results • PT-BR'
                        : 'Browse Goyabu directly',
                    icon: Icons.public,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF219C80), Color(0xFF50C878)],
                    ),
                    available: !_isSearchingSources,
                    isLoading: _isSearchingSources,
                    onTap: _goyabuResults.isNotEmpty
                        ? () => _selectSource(AnimeSource.goyabu)
                        : _openGoyabuWebsite,
                  ),

                  const SizedBox(height: 16),

                  _buildSourceCard(
                    title: 'SuperFlix',
                    subtitle: 'Movies / TV • open source player',
                    icon: Icons.movie_outlined,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF465A65), Color(0xFF82949D)],
                    ),
                    available: true,
                    isLoading: false,
                    onTap: _openSuperFlixWebsite,
                  ),

                  if (!_isSearchingSources &&
                      _aniDBResults.isEmpty &&
                      _animeFireResults.isEmpty &&
                      _goyabuResults.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _searchErrorMessage ??
                          'No source returned results. The source sites may be temporarily unavailable.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _searchSources,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry source search'),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Info adicional
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.locale.languageCode == 'pt'
                                ? 'Cada fonte pode ter episódios diferentes disponíveis'
                                : 'Each source may have different episodes available',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required bool available,
    required bool isLoading,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: available && !isLoading ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          gradient: available && !isLoading
              ? gradient
              : LinearGradient(
                  colors: [Colors.grey.shade800, Colors.grey.shade700],
                ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: available && !isLoading
              ? [
                  BoxShadow(
                    color: gradient.colors.first.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: available && !isLoading ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Ícone
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),

                  // Textos
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Indicador
                  if (isLoading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  else if (available)
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 20,
                    )
                  else
                    Icon(
                      Icons.block,
                      color: Colors.white.withValues(alpha: 0.5),
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
