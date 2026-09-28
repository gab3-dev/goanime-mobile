import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class GoyabuAnimeResult {
  final String name;
  final String url;
  final String imageUrl;

  const GoyabuAnimeResult({
    required this.name,
    required this.url,
    this.imageUrl = '',
  });
}

class GoyabuEpisodeResult {
  final String number;
  final int numericNumber;
  final String url;

  const GoyabuEpisodeResult({
    required this.number,
    required this.numericNumber,
    required this.url,
  });
}

class GoyabuResolvedStream {
  final String url;
  final Map<String, String> headers;
  final bool isDirectMedia;

  const GoyabuResolvedStream({
    required this.url,
    required this.headers,
    required this.isDirectMedia,
  });
}

/// Direct on-device search and episode client for Goyabu's PT-BR catalog.
/// It resolves direct media and Blogger streams without a hosted service.
class GoyabuService {
  static final shared = GoyabuService();
  static const baseUrl = 'https://goyabu.io';

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  static final _noncePattern = RegExp(r'"nonce"\s*:\s*"([a-f0-9]+)"');
  static final _episodeArrayPatterns = [
    RegExp(r'(?:const|let|var)\s+allEpisodes\s*=\s*(\[[\s\S]*?\])\s*;'),
    RegExp(r'episodes\s*[:=]\s*(\[[\s\S]*?\])'),
    RegExp(r'episodeList\s*[:=]\s*(\[[\s\S]*?\])'),
  ];
  static final _playersDataPattern = RegExp(
    r'var\s+playersData\s*=\s*(\[.*?\])\s*;',
    dotAll: true,
  );
  static final _bloggerTokenPatterns = [
    RegExp(r'''blogger_token\s*[:=]\s*["']([^"']+)["']'''),
    RegExp(r'''data-blogger-token\s*=\s*["']([^"']+)["']'''),
    RegExp(r'"blogger_token"\s*:\s*"([^"]+)"'),
  ];
  static final _bloggerUrlPattern = RegExp(
    r'https?://www\.blogger\.com/video\.g\?token=[A-Za-z0-9_-]+',
  );
  static final _videoPatterns = [
    RegExp(r'"file"\s*:\s*"(https?://[^"]+\.m3u8[^"]*)"'),
    RegExp(r'"file"\s*:\s*"(https?://[^"]+\.mp4[^"]*)"'),
    RegExp(r'''src\s*[:=]\s*["'](https?://[^"']+\.m3u8[^"']*)'''),
    RegExp(r'''src\s*[:=]\s*["'](https?://[^"']+\.mp4[^"']*)'''),
    RegExp(r'''source\s*[:=]\s*["'](https?://[^"']+\.m3u8[^"']*)'''),
  ];

  final http.Client _client;
  final String _baseUrl;

  GoyabuService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? GoyabuService.baseUrl).replaceFirst(
        RegExp(r'/$'),
        '',
      );

  Future<List<GoyabuAnimeResult>> searchAnime(String query) async {
    final normalized = query
        .trim()
        .replaceAll(RegExp(r'[-_]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return const [];

    try {
      final homepage = await _get(Uri.parse('$_baseUrl/'));
      final nonce = _noncePattern.firstMatch(homepage.body)?.group(1);
      if (nonce != null && nonce.isNotEmpty) {
        final apiUri = Uri.parse(
          '$_baseUrl/wp-json/animeonline/search/',
        ).replace(queryParameters: {'keyword': normalized, 'nonce': nonce});
        try {
          final response = await _get(apiUri, accept: 'application/json');
          final results = _parseApiSearch(response.body);
          if (results.isNotEmpty) return results;
        } catch (_) {
          // The HTML search remains an available path when the site's WP
          // endpoint is down or returns a challenge page.
        }
      }
    } catch (_) {
      // If the homepage/nonce request fails, try the public HTML search page.
    }

    return _searchHtml(normalized);
  }

  Future<List<GoyabuAnimeResult>> _searchHtml(String query) async {
    final uri = Uri.parse('$_baseUrl/').replace(queryParameters: {'s': query});
    final response = await _get(uri, accept: 'text/html');
    final document = html_parser.parse(response.body);
    final results = <GoyabuAnimeResult>[];
    final seen = <String>{};

    for (final anchor in document.querySelectorAll(
      'article a, .anime-item a, .post a',
    )) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (!href.contains('/anime/')) continue;
      final image = anchor.querySelector('img');
      final title =
          (anchor.querySelector('h3')?.text ??
                  anchor.querySelector('h2')?.text ??
                  image?.attributes['alt'] ??
                  '')
              .trim();
      if (title.isEmpty) continue;

      final animeUrl = _resolveUrl(href);
      if (!seen.add(animeUrl)) continue;
      final imageReference =
          image?.attributes['src'] ?? image?.attributes['data-src'] ?? '';
      results.add(
        GoyabuAnimeResult(
          name: title,
          url: animeUrl,
          imageUrl: _resolveUrl(imageReference),
        ),
      );
    }
    return results;
  }

  List<GoyabuAnimeResult> _parseApiSearch(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];

    final results = <GoyabuAnimeResult>[];
    final seen = <String>{};
    for (final value in decoded.values) {
      if (value is! Map) continue;
      final title = value['title']?.toString().trim() ?? '';
      final rawUrl = value['url']?.toString().trim() ?? '';
      if (title.isEmpty || rawUrl.isEmpty) continue;
      final url = _resolveUrl(rawUrl);
      if (!seen.add(url)) continue;
      results.add(
        GoyabuAnimeResult(
          name: title,
          url: url,
          imageUrl: _resolveUrl(value['img']?.toString() ?? ''),
        ),
      );
    }
    return results;
  }

  Future<List<GoyabuEpisodeResult>> getAnimeEpisodes(String animeUrl) async {
    final response = await _get(Uri.parse(animeUrl), accept: 'text/html');
    final body = response.body;
    List<dynamic>? rawEpisodes;

    for (final pattern in _episodeArrayPatterns) {
      final match = pattern.firstMatch(body);
      if (match == null) continue;
      try {
        final decoded = jsonDecode(match.group(1)!);
        if (decoded is List) {
          rawEpisodes = decoded;
          break;
        }
      } on FormatException {
        // Try the next supported page assignment format.
      }
    }

    if (rawEpisodes != null) {
      final episodes = <GoyabuEpisodeResult>[];
      var fallbackNumber = 1;
      for (final value in rawEpisodes) {
        if (value is! Map) continue;
        final id = value['id']?.toString() ?? '';
        if (id.isEmpty || id == '0') continue;
        final rawNumber = value['episodio']?.toString() ?? '';
        final parsedNumber = int.tryParse(rawNumber);
        final number = parsedNumber ?? fallbackNumber;
        fallbackNumber = number + 1;
        episodes.add(
          GoyabuEpisodeResult(
            number: rawNumber.isEmpty ? '$number' : rawNumber,
            numericNumber: number,
            url: Uri.parse(
              '$_baseUrl/',
            ).replace(queryParameters: {'p': id}).toString(),
          ),
        );
      }
      episodes.sort((a, b) => a.numericNumber.compareTo(b.numericNumber));
      if (episodes.isNotEmpty) return episodes;
    }

    return _parseEpisodeLinks(body);
  }

  List<GoyabuEpisodeResult> _parseEpisodeLinks(String body) {
    final document = html_parser.parse(body);
    final episodes = <GoyabuEpisodeResult>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (!href.contains('/?p=') && !href.contains('/episode/')) continue;
      final url = _resolveUrl(href);
      if (!seen.add(url)) continue;
      final rawNumber = anchor.attributes['data-episode-number'] ?? '';
      final number = int.tryParse(rawNumber) ?? episodes.length + 1;
      episodes.add(
        GoyabuEpisodeResult(
          number: rawNumber.isEmpty ? '$number' : rawNumber,
          numericNumber: number,
          url: url,
        ),
      );
    }
    episodes.sort((a, b) => a.numericNumber.compareTo(b.numericNumber));
    return episodes;
  }

  Future<GoyabuResolvedStream> getEpisodeStreamUrl(String episodeUrl) async {
    final page = await _get(Uri.parse(episodeUrl), accept: 'text/html');
    final body = page.body;
    final document = html_parser.parse(body);
    _throwIfChallenge(document, 'episode playback');

    final iframeUrl = document.querySelector('iframe')?.attributes['src'];
    if (iframeUrl != null && iframeUrl.isNotEmpty) {
      final resolved = _resolveUrl(iframeUrl);
      return _streamResult(resolved, isDirectMedia: _looksLikeMedia(resolved));
    }

    final videoUrl =
        document.querySelector('video source')?.attributes['src'] ??
        document.querySelector('video')?.attributes['src'] ??
        document
            .querySelector('video[data-video-src]')
            ?.attributes['data-video-src'];
    if (videoUrl != null && videoUrl.isNotEmpty) {
      return _streamResult(_resolveUrl(videoUrl), isDirectMedia: true);
    }

    final playerData = _extractPlayerData(body);
    if (playerData.token.isNotEmpty) {
      try {
        final decodedUrl = await _decodeBloggerToken(playerData.token);
        return _streamResult(decodedUrl, isDirectMedia: true);
      } catch (_) {
        // The embed URL remains available to the WebView if AJAX resolution
        // fails or the source changes its decoder response.
      }
    }

    for (final pattern in _videoPatterns) {
      final match = pattern.firstMatch(body);
      if (match != null && match.group(1) != null) {
        return _streamResult(match.group(1)!, isDirectMedia: true);
      }
    }

    if (playerData.bloggerUrl.isNotEmpty) {
      return _streamResult(playerData.bloggerUrl, isDirectMedia: false);
    }
    throw const FormatException('Goyabu episode page did not expose a stream');
  }

  Future<String> _decodeBloggerToken(String token) async {
    final uri = Uri.parse('$_baseUrl/wp-admin/admin-ajax.php');
    final response = await _client
        .post(
          uri,
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Referer': '$_baseUrl/',
            'User-Agent': _userAgent,
            'X-Requested-With': 'XMLHttpRequest',
          },
          body: {'action': 'decode_blogger_video', 'token': token},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Goyabu stream resolver failed (${response.statusCode})');
    }

    final body = response.body.trim();
    if (body.startsWith('http://') || body.startsWith('https://')) {
      return _validateStreamUrl(body);
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException(
        'Goyabu stream resolver returned invalid data',
      );
    }
    final data = decoded['data'];
    if (data is Map) {
      final play = data['play'];
      if (play is List) {
        String bestUrl = '';
        var bestSize = -1.0;
        for (final item in play.whereType<Map>()) {
          final source = item['src']?.toString() ?? '';
          final size = double.tryParse(item['size']?.toString() ?? '') ?? 0;
          if (source.isNotEmpty && size >= bestSize) {
            bestUrl = source;
            bestSize = size;
          }
        }
        if (bestUrl.isNotEmpty) return _validateStreamUrl(bestUrl);
      }
    }

    for (final object in [decoded, if (data is Map) data]) {
      for (final key in ['url', 'file', 'src', 'video_url', 'stream_url']) {
        final value = object[key]?.toString() ?? '';
        if (value.startsWith('http://') || value.startsWith('https://')) {
          return _validateStreamUrl(value);
        }
      }
    }
    throw const FormatException('Goyabu returned no playable video URL');
  }

  ({String token, String bloggerUrl}) _extractPlayerData(String body) {
    var token = '';
    var bloggerUrl = '';
    final match = _playersDataPattern.firstMatch(body);
    if (match != null) {
      try {
        final players = jsonDecode(match.group(1)!);
        if (players is List && players.isNotEmpty && players.first is Map) {
          final player = players.first as Map;
          token = player['blogger_token']?.toString() ?? '';
          bloggerUrl = player['url']?.toString() ?? '';
        }
      } on FormatException {
        // Fall through to the standalone token patterns below.
      }
    }
    if (token.isEmpty) {
      for (final pattern in _bloggerTokenPatterns) {
        token = pattern.firstMatch(body)?.group(1) ?? '';
        if (token.isNotEmpty) break;
      }
    }
    if (bloggerUrl.isEmpty) {
      bloggerUrl = _bloggerUrlPattern.firstMatch(body)?.group(0) ?? '';
    }
    return (token: token, bloggerUrl: bloggerUrl);
  }

  GoyabuResolvedStream _streamResult(
    String url, {
    required bool isDirectMedia,
  }) {
    return GoyabuResolvedStream(
      url: _validateStreamUrl(url),
      headers: {'Referer': '$_baseUrl/', 'User-Agent': _userAgent},
      isDirectMedia: isDirectMedia,
    );
  }

  String _validateStreamUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('Goyabu returned an invalid stream URL');
    }
    return uri.toString();
  }

  bool _looksLikeMedia(String value) {
    final path = Uri.tryParse(value)?.path.toLowerCase() ?? '';
    return path.endsWith('.mp4') || path.endsWith('.m3u8');
  }

  void _throwIfChallenge(dynamic document, String operation) {
    final title = document.querySelector('title')?.text ?? '';
    final body = document.body?.text ?? '';
    final text = '$title $body'.toLowerCase();
    if (text.contains('just a moment') ||
        text.contains('checking your browser') ||
        text.contains('cloudflare')) {
      throw Exception('Goyabu requires a browser check ($operation)');
    }
  }

  Future<http.Response> _get(Uri uri, {String? accept}) async {
    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': accept ?? '*/*',
            'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
            'Referer': '$_baseUrl/',
            'User-Agent': _userAgent,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Goyabu request failed (${response.statusCode})');
    }
    return response;
  }

  String _resolveUrl(String reference) {
    if (reference.isEmpty) return '';
    return Uri.parse('$_baseUrl/').resolve(reference).toString();
  }
}
