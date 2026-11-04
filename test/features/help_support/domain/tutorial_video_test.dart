import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/help_support/domain/entities/localized_text.dart';
import 'package:orange_one/features/help_support/domain/entities/tutorial_video.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  test('accepts a video ID and the usual YouTube links', () {
    for (final value in [
      id,
      ' $id ',
      'https://www.youtube.com/watch?v=$id',
      'https://youtube.com/watch?v=$id&t=42s',
      'https://m.youtube.com/watch?v=$id',
      'https://youtu.be/$id',
      'https://youtu.be/$id?si=share',
      'https://www.youtube.com/shorts/$id',
      'https://www.youtube.com/embed/$id',
      'https://www.youtube.com/live/$id',
    ]) {
      expect(TutorialVideo.videoIdFrom(value), id, reason: value);
    }
  });

  test('rejects anything that is not a YouTube video', () {
    for (final value in [
      null,
      '',
      'abc',
      '${id}x',
      'https://evil.example.com/watch?v=$id',
      'https://youtube.com.evil.example/watch?v=$id',
      'https://www.youtube.com/watch?v=short',
      'https://www.youtube.com/playlist?list=PL123',
      'https://www.youtube.com/channel/UC123',
      'javascript:alert(1)',
      'ftp://youtu.be/$id',
    ]) {
      expect(TutorialVideo.videoIdFrom(value), isNull, reason: value);
    }
  });

  test('rejects malformed percent-encoding instead of throwing', () {
    for (final value in [
      'https://www.youtube.com/%FF',
      'https://youtu.be/%FF',
      'https://www.youtube.com/shorts/%FF',
      'https://www.youtube.com/watch?v=%FF',
      'https://www.youtube.com/watch?v=$id&x=%FF',
      'https://m.youtube.com/watch?v=%C3%28',
    ]) {
      expect(TutorialVideo.videoIdFrom(value), isNull, reason: value);
    }
    // Valid encodings still work.
    expect(
      TutorialVideo.videoIdFrom('https://www.youtube.com/watch?v=$id'),
      id,
    );
  });

  test('always opens the canonical YouTube page and preview', () {
    expect(
      TutorialVideo(
        id: 'a',
        title: LocalizedText.single('t'),
        description: const LocalizedText({}),
        youtubeVideoId: id,
        thumbnail: TutorialVideo.defaultThumbnail(id),
        order: 1,
      ).watchUrl.toString(),
      'https://www.youtube.com/watch?v=$id',
    );
    expect(
      TutorialVideo.defaultThumbnail(id).toString(),
      'https://i.ytimg.com/vi/$id/mqdefault.jpg',
    );
  });

  test('text follows the app language, then English, then any text', () {
    const text = LocalizedText({'en': 'Hello', 'de': 'Hallo', 'fr': ' '});
    expect(text.resolve('de'), 'Hallo');
    expect(text.resolve('fr'), 'Hello');
    expect(text.resolve('ta'), 'Hello');
    expect(const LocalizedText({'it': 'Ciao'}).resolve('tr'), 'Ciao');
    expect(LocalizedText.single('Same').resolve('ta'), 'Same');
    expect(const LocalizedText({'en': '  '}).isEmpty, isTrue);
  });
}
