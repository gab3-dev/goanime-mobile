import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class AniDBAnimeResult {
  final String name;
  final String url;
  final String imageUrl;

  const AniDBAnimeResult({
    required this.name,
    required this.url,
    this.imageUrl = '',
  });
}

class AniDBEpisodeResult {
  final String number;
  final int numericNumber;
  final String url;
  final String title;
  final bool isFiller;

  const AniDBEpisodeResult({
    required this.number,
    required this.numericNumber,
    required this.url,
    this.title = '',
    this.isFiller = false,
  });
}

class AniDBLanguage {
  final String code;
  final String name;

  const AniDBLanguage({required this.code, required this.name});
}

class AniDBResolvedStream {
  final String url;
  final Map<String, String> headers;
  final String audioLanguage;

  const AniDBResolvedStream({
    required this.url,
    required this.headers,
    required this.audioLanguage,
  });
}

/// Direct, on-device client for the AniDB website and its playback endpoints.
/// No GoAnime server is involved; callers may inject an HTTP client for tests.
class AniDBService {
  static final shared = AniDBService();

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final http.Client _client;
  final String _baseUrl;

  AniDBService({http.Client? client, String baseUrl = 'https://anidb.app'})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  Future<List<AniDBAnimeResult>> searchAnime(String query) async {
    if (query.trim().isEmpty) return const [];

    final uri = Uri.parse(
      '$_baseUrl/browse',
    ).replace(queryParameters: {'q': query.trim()});
    final response = await _get(uri, accept: 'text/html');
    final document = html_parser.parse(response.body);
    _throwIfChallenge(document, 'search');

    final results = <AniDBAnimeResult>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      final path = Uri.tryParse(href)?.path ?? href;
      final match = RegExp(r'^/anime/([a-z0-9-]+)-(\d+)/?$').firstMatch(path);
      if (match == null) continue;

      final url = _resolveUrl(href);
      if (!seen.add(url)) continue;

      final image = anchor.querySelector('img');
      final name = (anchor.attributes['title'] ?? '').trim().isNotEmpty
          ? anchor.attributes['title']!.trim()
          : (image?.attributes['alt'] ?? '').trim();
      if (name.isEmpty) continue;

      results.add(
        AniDBAnimeResult(
          name: name,
          url: url,
          imageUrl: _resolveUrl(image?.attributes['src'] ?? ''),
        ),
      );
    }
    return results;
  }

  Future<List<AniDBEpisodeResult>> getAnimeEpisodes(String animeUrl) async {
    final animeId = _extractId(animeUrl, r'(?:/anime/[^/]+-|^)(\d+)/?$');
    final uri = Uri.parse('$_baseUrl/api/frontend/anime/$animeId/episodes');
    final response = await _get(uri, accept: 'application/json');
    final payload = _decodeObject(response.body, 'episodes');
    final rawEpisodes = payload['episodes'];
    if (rawEpisodes is! List) {
      throw const FormatException('AniDB response did not contain episodes');
    }

    final episodes = <AniDBEpisodeResult>[];
    for (final item in rawEpisodes) {
      if (item is! Map) continue;
      final id = _intValue(item['id']);
      final number = _intValue(item['number']);
      if (id == 0) continue;
      episodes.add(
        AniDBEpisodeResult(
          number: '$number',
          numericNumber: number,
          url: '$_baseUrl/episode/$id',
          title: item['title']?.toString() ?? '',
          isFiller: item['filler'] == true,
        ),
      );
    }
    episodes.sort((a, b) => a.numericNumber.compareTo(b.numericNumber));
    if (episodes.isEmpty) {
      throw const FormatException('AniDB returned no playable episodes');
    }
    return episodes;
  }

  Future<List<AniDBLanguage>> getAvailableLanguages(String episodeUrl) async {
    final episodeId = _extractId(episodeUrl, r'(?:/episode/|^)(\d+)/?$');
    final uri = Uri.parse(
      '$_baseUrl/api/frontend/episode/$episodeId/languages',
    );
    final response = await _get(uri, accept: 'application/json');
    final payload = _decodeObject(response.body, 'languages');
    final rawLanguages = payload['languages'];
    if (rawLanguages is! List) {
      throw const FormatException('AniDB response did not contain languages');
    }

    return rawLanguages
        .whereType<Map>()
        .where(
          (language) => (language['embed_url']?.toString() ?? '').isNotEmpty,
        )
        .map(
          (language) => AniDBLanguage(
            code: language['code']?.toString() ?? '',
            name: language['name']?.toString() ?? '',
          ),
        )
        .toList();
  }

  Future<AniDBResolvedStream> getEpisodeStreamUrl(
    String episodeUrl, {
    String languageCode = 'jpn',
    String quality = 'best',
  }) async {
    final episodeId = _extractId(episodeUrl, r'(?:/episode/|^)(\d+)/?$');
    final uri = Uri.parse(
      '$_baseUrl/api/frontend/episode/$episodeId/languages',
    );
    final response = await _get(uri, accept: 'application/json');
    final payload = _decodeObject(response.body, 'languages');
    final rawLanguages = payload['languages'];
    if (rawLanguages is! List) {
      throw const FormatException('AniDB response did not contain languages');
    }

    final languages = rawLanguages.whereType<Map>().toList();
    final selected = languages.firstWhere(
      (language) =>
          (language['code']?.toString().toLowerCase() ?? '') ==
              languageCode.toLowerCase() &&
          (language['embed_url']?.toString() ?? '').isNotEmpty,
      orElse: () => languages.firstWhere(
        (language) => (language['embed_url']?.toString() ?? '').isNotEmpty,
        orElse: () => <String, dynamic>{},
      ),
    );
    final embedUrl = selected['embed_url']?.toString() ?? '';
    if (embedUrl.isEmpty) {
      throw const FormatException('AniDB has no playable audio language');
    }

    final embedResponse = await _get(Uri.parse(_resolveUrl(embedUrl)));
    final playlistMatch = RegExp(
      r'''file:\s*['"]([^'"]+\.m3u8[^'"]*)['"]''',
    ).firstMatch(embedResponse.body);
    if (playlistMatch == null) {
      throw const FormatException('AniDB player page did not contain a stream');
    }

    final masterUrl = _resolveUrl(playlistMatch.group(1)!);
    final streamUrl = await _selectQuality(masterUrl, quality);
    final selectedCode = selected['code']?.toString() ?? languageCode;
    return AniDBResolvedStream(
      url: streamUrl,
      headers: {'Referer': '$_baseUrl/', 'User-Agent': _userAgent},
      audioLanguage: selectedCode,
    );
  }

  Future<String> _selectQuality(String masterUrl, String quality) async {
    final heightMatch = RegExp(r'(\d{3,4})').firstMatch(quality);
    if (heightMatch == null) return masterUrl;
    final wantedHeight = int.tryParse(heightMatch.group(1)!);
    if (wantedHeight == null) return masterUrl;

    try {
      final response = await _get(Uri.parse(masterUrl));
      final lines = const LineSplitter().convert(response.body);
      for (var index = 0; index + 1 < lines.length; index++) {
        final variant = RegExp(
          r'RESOLUTION=\d+x(\d+)',
        ).firstMatch(lines[index]);
        if (variant == null ||
            int.tryParse(variant.group(1)!) != wantedHeight) {
          continue;
        }
        final reference = lines[index + 1].trim();
        if (reference.isNotEmpty && !reference.startsWith('#')) {
          return _resolveUrl(reference, base: masterUrl);
        }
      }
    } catch (_) {
      // The master playlist itself remains playable and lets the native player
      // choose an available variant.
    }
    return masterUrl;
  }

  Future<http.Response> _get(Uri uri, {String? accept}) async {
    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': accept ?? '*/*',
            'Accept-Language': 'en-US,en;q=0.9',
            'Referer': '$_baseUrl/',
            'User-Agent': _userAgent,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('AniDB request failed (${response.statusCode})');
    }
    return response;
  }

  Map<String, dynamic> _decodeObject(String body, String operation) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw FormatException('AniDB returned invalid $operation data');
    }
    return value;
  }

  String _extractId(String input, String pattern) {
    final value = input.trim();
    final match = RegExp(
      pattern,
    ).firstMatch(Uri.tryParse(value)?.path ?? value);
    if (match == null || match.group(1)!.isEmpty) {
      throw FormatException('Invalid AniDB URL: $input');
    }
    return match.group(1)!;
  }

  String _resolveUrl(String reference, {String? base}) {
    if (reference.isEmpty) return '';
    final origin = Uri.parse(base ?? '$_baseUrl/');
    return origin.resolve(reference).toString();
  }

  void _throwIfChallenge(dynamic document, String operation) {
    final title = document.querySelector('title')?.text ?? '';
    final body = document.body?.text ?? '';
    final text = '$title $body'.toLowerCase();
    if (text.contains('just a moment') ||
        text.contains('checking your browser') ||
        text.contains('cloudflare')) {
      throw Exception(
        'AniDB blocked the $operation request with a browser check',
      );
    }
  }

  static int _intValue(dynamic value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;
}
