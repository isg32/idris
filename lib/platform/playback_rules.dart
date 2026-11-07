import 'dart:math' as math;

import '../data/models.dart';

/// What happens when a track plays to its end.
enum AfterTrack { replay, next, stop }

/// Decides what follows a finished track.
///
/// [repeatDone] counts plays of this track including the one that just
/// ended. Order of precedence: a sleep timer set to "end of track" stops;
/// loop-one replays; a repeat count replays until it's reached, then stops
/// or moves on; otherwise the next track, or the end of the queue.
AfterTrack afterTrackEnds({
  required bool sleepAtEnd,
  required bool loopOne,
  required int? repeatTarget,
  required int repeatDone,
  required RepeatEnd repeatEnd,
  required bool hasNext,
}) {
  if (sleepAtEnd) return AfterTrack.stop;
  if (loopOne) return AfterTrack.replay;
  if (repeatTarget != null) {
    if (repeatDone < repeatTarget) return AfterTrack.replay;
    if (repeatEnd == RepeatEnd.stop) return AfterTrack.stop;
  }
  return hasNext ? AfterTrack.next : AfterTrack.stop;
}

/// [queue] shuffled with the track at [index] kept first.
List<T> shuffledFrom<T>(List<T> queue, int index, {math.Random? random}) {
  if (queue.isEmpty) return const [];
  final rest = [...queue]..removeAt(index);
  rest.shuffle(random);
  return [queue[index], ...rest];
}
