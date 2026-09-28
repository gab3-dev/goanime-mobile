import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/anidb_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AniDBService', () {
    test(
      'parses unique anime cards and resolves relative poster paths',
      () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/browse');
          expect(request.url.queryParameters['q'], 'cowboy bebop');
          return http.Response('''<html><body>
            <a href="/anime/cowboy-bebop-42" title="Cowboy Bebop">
              <img src="/covers/42.jpg" alt="Poster">
            </a>
            <a href="/anime/cowboy-bebop-42"><img alt="Duplicate"></a>
            <a href="/browse?sort=popular">Browse</a>
          </body></html>''', 200);
        });

        final results = await AniDBService(
          client: client,
          baseUrl: 'https://anidb.test',
        ).searchAnime('cowboy bebop');

        expect(results, hasLength(1));
        expect(results.single.name, 'Cowboy Bebop');
        expect(results.single.url, 'https://anidb.test/anime/cowboy-bebop-42');
        expect(results.single.imageUrl, 'https://anidb.test/covers/42.jpg');
      },
    );

    test('sorts episodes and drops entries without a playable id', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/frontend/anime/42/episodes');
        return http.Response(
          '{"episodes":['
          '{"id":20051,"number":3,"filler":true},'
          '{"id":20049,"number":1,"title":"First"},'
          '{"id":0,"number":4}]}',
          200,
        );
      });

      final episodes = await AniDBService(
        client: client,
        baseUrl: 'https://anidb.test',
      ).getAnimeEpisodes('https://anidb.test/anime/cowboy-bebop-42');

      expect(episodes.map((episode) => episode.number), ['1', '3']);
      expect(episodes.first.url, 'https://anidb.test/episode/20049');
      expect(episodes.last.isFiller, isTrue);
    });

    test('resolves requested audio language and HLS quality variant', () async {
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/api/frontend/episode/20049/languages':
            return http.Response(
              '{"languages":['
              '{"code":"jpn","name":"Japanese","embed_url":"/embed/jpn"},'
              '{"code":"eng","name":"English","embed_url":"/embed/eng"}]}',
              200,
            );
          case '/embed/eng':
            return http.Response(
              "<script>jwplayer().setup({file: 'https://hls.test/master.m3u8'});</script>",
              200,
            );
          case '/master.m3u8':
            return http.Response(
              '#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\n1080.m3u8\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720\n720.m3u8\n',
              200,
            );
          default:
            return http.Response('not found', 404);
        }
      });

      final stream =
          await AniDBService(
            client: client,
            baseUrl: 'https://anidb.test',
          ).getEpisodeStreamUrl(
            'https://anidb.test/episode/20049',
            languageCode: 'eng',
            quality: '720p',
          );

      expect(stream.url, 'https://hls.test/720.m3u8');
      expect(stream.audioLanguage, 'eng');
      expect(stream.headers['Referer'], 'https://anidb.test/');
    });
  });
}
