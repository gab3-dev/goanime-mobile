import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/goyabu_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GoyabuService', () {
    test('uses the source search endpoint and resolves result URLs', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/') {
          return http.Response(
            '<script>var glosAP = {"nonce":"abc123"};</script>',
            200,
          );
        }
        expect(request.url.path, '/wp-json/animeonline/search/');
        expect(request.url.queryParameters['keyword'], 'naruto shippuden');
        expect(request.url.queryParameters['nonce'], 'abc123');
        return http.Response(
          '{"41411":{"title":"Naruto Clássico Dublado",'
          '"url":"/anime/naruto-classico","img":"/covers/naruto.jpg"}}',
          200,
        );
      });

      final results = await GoyabuService(
        client: client,
        baseUrl: 'https://goyabu.test',
      ).searchAnime('naruto-shippuden');

      expect(results, hasLength(1));
      expect(results.single.name, 'Naruto Clássico Dublado');
      expect(results.single.url, 'https://goyabu.test/anime/naruto-classico');
      expect(results.single.imageUrl, 'https://goyabu.test/covers/naruto.jpg');
    });

    test('falls back to HTML search if the source nonce is absent', () async {
      final client = MockClient((request) async {
        if (request.url.queryParameters.isEmpty) {
          return http.Response('<html><body>No nonce</body></html>', 200);
        }
        expect(request.url.queryParameters['s'], 'one piece');
        return http.Response(
          '<article><a href="/anime/one-piece"><h3>One Piece</h3>'
          '<img src="/covers/one-piece.jpg"></a></article>',
          200,
        );
      });

      final results = await GoyabuService(
        client: client,
        baseUrl: 'https://goyabu.test',
      ).searchAnime('one piece');

      expect(results, hasLength(1));
      expect(results.single.url, 'https://goyabu.test/anime/one-piece');
    });

    test('parses and sorts episodes from the page JavaScript', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/anime/one-piece');
        return http.Response(
          '<script>const allEpisodes = ['
          '{"id":2,"episodio":"2"},'
          '{"id":1,"episodio":"1"}];</script>',
          200,
        );
      });

      final episodes = await GoyabuService(
        client: client,
        baseUrl: 'https://goyabu.test',
      ).getAnimeEpisodes('https://goyabu.test/anime/one-piece');

      expect(episodes.map((episode) => episode.number), ['1', '2']);
      expect(episodes.first.url, 'https://goyabu.test/?p=1');
      expect(episodes.last.url, 'https://goyabu.test/?p=2');
    });

    test('returns direct video sources with Goyabu playback headers', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['p'], '41414');
        return http.Response(
          '<video><source src="https://cdn.test/episode.m3u8"></video>',
          200,
        );
      });

      final stream = await GoyabuService(
        client: client,
        baseUrl: 'https://goyabu.test',
      ).getEpisodeStreamUrl('https://goyabu.test/?p=41414');

      expect(stream.url, 'https://cdn.test/episode.m3u8');
      expect(stream.isDirectMedia, isTrue);
      expect(stream.headers['Referer'], 'https://goyabu.test/');
    });

    test(
      'decodes the Blogger token and chooses the highest available quality',
      () async {
        final client = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              '<script>var playersData = [{"blogger_token":"dGVzdA==",'
              '"url":"https://www.blogger.com/video.g?token=Fallback"}];</script>',
              200,
            );
          }
          expect(request.url.path, '/wp-admin/admin-ajax.php');
          expect(request.body, contains('action=decode_blogger_video'));
          expect(request.body, contains('token=dGVzdA%3D%3D'));
          return http.Response(
            '{"success":true,"data":{"play":['
            '{"src":"https://cdn.test/360.mp4","size":360},'
            '{"src":"https://cdn.test/720.mp4","size":720}]}}',
            200,
          );
        });

        final stream = await GoyabuService(
          client: client,
          baseUrl: 'https://goyabu.test',
        ).getEpisodeStreamUrl('https://goyabu.test/?p=41414');

        expect(stream.url, 'https://cdn.test/720.mp4');
        expect(stream.isDirectMedia, isTrue);
      },
    );

    test(
      'keeps the Blogger embed as a fallback when its decoder has no stream',
      () async {
        final client = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              '<script>var playersData = [{"blogger_token":"dGVzdA==",'
              '"url":"https://www.blogger.com/video.g?token=Fallback"}];</script>',
              200,
            );
          }
          return http.Response(
            '{"success":false,"data":{"message":"No video"}}',
            200,
          );
        });

        final stream = await GoyabuService(
          client: client,
          baseUrl: 'https://goyabu.test',
        ).getEpisodeStreamUrl('https://goyabu.test/?p=41414');

        expect(stream.url, 'https://www.blogger.com/video.g?token=Fallback');
        expect(stream.isDirectMedia, isFalse);
      },
    );
  });
}
