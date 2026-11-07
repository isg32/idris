import 'package:flutter_test/flutter_test.dart';
import 'package:idris/platform/playlist_scraper.dart';

Map<String, Object?> lockup(String id, String type, {String? length}) => {
  'lockupViewModel': {
    'contentId': id,
    'contentType': type,
    'contentImage': {
      'thumbnailViewModel': {
        'overlays': [
          {
            'thumbnailBottomOverlayViewModel': {
              'badges': [
                {
                  'thumbnailBadgeViewModel': {'text': ?length},
                },
              ],
            },
          },
        ],
      },
    },
    'metadata': {
      'lockupMetadataViewModel': {
        'title': {'content': 'Title $id'},
        'metadata': {
          'contentMetadataViewModel': {
            'metadataRows': [
              {
                'metadataParts': [
                  {
                    'text': {'content': 'Channel $id'},
                  },
                ],
              },
            ],
          },
        },
      },
    },
  },
};

void main() {
  test('reads lockupViewModel items (YouTube\'s current format)', () {
    final page = parsePage({
      'itemSectionRenderer': {
        'contents': [
          lockup('aaa', 'LOCKUP_CONTENT_TYPE_VIDEO', length: '26:13'),
          lockup('bbb', 'LOCKUP_CONTENT_TYPE_VIDEO', length: '1:02:14'),
          // A recommended playlist, not a video.
          lockup('PLx', 'LOCKUP_CONTENT_TYPE_PLAYLIST'),
        ],
      },
      'continuationItemViewModel': {
        'continuationCommand': {
          'innertubeCommand': {
            'continuationCommand': {'token': 'next-page'},
          },
        },
      },
    });
    expect(page.videos.map((v) => v.id), ['aaa', 'bbb']);
    expect(page.videos.first.title, 'Title aaa');
    expect(page.videos.first.channel, 'Channel aaa');
    expect(page.videos.first.duration, const Duration(minutes: 26, seconds: 13));
    expect(page.videos[1].duration, const Duration(hours: 1, minutes: 2, seconds: 14));
    expect(page.continuation, 'next-page');
  });

  test('reads playlistVideoRenderer items (the old format)', () {
    final page = parsePage([
      {
        'playlistVideoRenderer': {
          'videoId': 'old',
          'title': {
            'runs': [
              {'text': 'Old title'},
            ],
          },
          'shortBylineText': {
            'runs': [
              {'text': 'Old channel'},
            ],
          },
          'lengthSeconds': '125',
        },
      },
      {
        'continuationItemRenderer': {
          'continuationEndpoint': {
            'continuationCommand': {'token': 'old-token'},
          },
        },
      },
    ]);
    expect(page.videos.single.title, 'Old title');
    expect(page.videos.single.duration, const Duration(seconds: 125));
    expect(page.continuation, 'old-token');
  });

  test('a page with no items is empty', () {
    final page = parsePage({'foo': 'bar'});
    expect(page.videos, isEmpty);
    expect(page.continuation, isNull);
  });

  test('ytInitialData is found in a page', () {
    expect(
      extractInitialData('<script>var ytInitialData = {"a":1};</script>'),
      {'a': 1},
    );
    expect(extractInitialData('<html></html>'), isNull);
    // The escaped-string form YouTube sometimes sends.
    expect(
      extractInitialData(
        r"<script>var ytInitialData = '\x7b\x22a\x22:\x22\u00e9\x22\x7d';</script>",
      ),
      {'a': 'é'},
    );
  });

  test('clock text parses', () {
    expect(parseClock('4:05'), const Duration(minutes: 4, seconds: 5));
    expect(parseClock('LIVE'), isNull);
  });
}
