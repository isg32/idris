import 'dart:math' as math;

import '../data/models.dart';

/// What happens when a track plays to its end.
enum AfterTrack {
  replay,
  next,

  /// Back to the first track (looping the playlist).
  wrap,
  stop,
}

/// The loop button cycles through these, as in Spotify and Apple Music.
enum Loop {
  off,

  /// The whole queue, from the top again after the last track.
  all,

  /// The current track, forever.
  one;

  Loop get next => Loop.values[(index + 1) % Loop.values.length];
}

/// Decides what follows a finished track.
///
/// [repeatDone] counts plays of this track including the one that just
/// ended. Order of precedence: a sleep timer set to "end of track" stops;
/// loop-one replays; a repeat count replays until it's reached, then stops
/// or moves on; otherwise the next track, or after the last one the first
/// again (loop all) or the end.
AfterTrack afterTrackEnds({
  required bool sleepAtEnd,
  required Loop loop,
  required int? repeatTarget,
  required int repeatDone,
  required RepeatEnd repeatEnd,
  required bool hasNext,
}) {
  if (sleepAtEnd) return AfterTrack.stop;
  if (loop == Loop.one) return AfterTrack.replay;
  if (repeatTarget != null) {
    if (repeatDone < repeatTarget) return AfterTrack.replay;
    if (repeatEnd == RepeatEnd.stop) return AfterTrack.stop;
  }
  if (hasNext) return AfterTrack.next;
  return loop == Loop.all ? AfterTrack.wrap : AfterTrack.stop;
}

/// [queue] shuffled with the track at [index] kept first.
List<T> shuffledFrom<T>(List<T> queue, int index, {math.Random? random}) {
  if (queue.isEmpty) return const [];
  final rest = [...queue]..removeAt(index);
  rest.shuffle(random);
  return [queue[index], ...rest];
}
