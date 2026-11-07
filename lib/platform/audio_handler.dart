import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/library.dart';
import '../data/models.dart';
import 'cache_manager.dart';
import 'playback_rules.dart';
import 'youtube.dart';

/// Where the session is, for the pages.
@immutable
class SessionState {
  const SessionState({
    this.queue = const [],
    this.index = 0,
    this.source = '',
    this.loading = false,
    this.problem,
    this.cached = false,
    this.kbps = 0,
    this.loop = Loop.off,
    this.repeatTarget,
    this.repeatDone = 0,
    this.repeatEnd = RepeatEnd.next,
    this.shuffle = false,
    this.sleepEndsAt,
    this.sleepAtEndOfTrack = false,
  });

  final List<Track> queue;
  final int index;

  /// The playlist the session came from ("Daily chants").
  final String source;

  /// Opening the current track (finding a stream).
  final bool loading;

  /// Shown while a stream failed and another way is tried.
  final String? problem;

  /// Playing from a complete file on the phone.
  final bool cached;
  final int kbps;

  final Loop loop;

  /// Repeat this track N times; null when off.
  final int? repeatTarget;

  /// Plays of the current track so far in this repeat (1 while the first
  /// plays).
  final int repeatDone;
  final RepeatEnd repeatEnd;
  final bool shuffle;
  final DateTime? sleepEndsAt;
  final bool sleepAtEndOfTrack;

  bool get active => queue.isNotEmpty;
  Track? get current => index < queue.length ? queue[index] : null;
  bool get hasNext => index + 1 < queue.length;

  /// Next is possible: another track, or the first again when looping.
  bool get canSkip => hasNext || (loop == Loop.all && queue.length > 1);
  List<Track> get upNext =>
      index + 1 < queue.length ? queue.sublist(index + 1) : const [];

  SessionState copyWith({
    List<Track>? queue,
    int? index,
    String? source,
    bool? loading,
    String? Function()? problem,
    bool? cached,
    int? kbps,
    Loop? loop,
    int? Function()? repeatTarget,
    int? repeatDone,
    RepeatEnd? repeatEnd,
    bool? shuffle,
    DateTime? Function()? sleepEndsAt,
    bool? sleepAtEndOfTrack,
  }) => SessionState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    source: source ?? this.source,
    loading: loading ?? this.loading,
    problem: problem != null ? problem() : this.problem,
    cached: cached ?? this.cached,
    kbps: kbps ?? this.kbps,
    loop: loop ?? this.loop,
    repeatTarget: repeatTarget != null ? repeatTarget() : this.repeatTarget,
    repeatDone: repeatDone ?? this.repeatDone,
    repeatEnd: repeatEnd ?? this.repeatEnd,
    shuffle: shuffle ?? this.shuffle,
    sleepEndsAt: sleepEndsAt != null ? sleepEndsAt() : this.sleepEndsAt,
    sleepAtEndOfTrack: sleepAtEndOfTrack ?? this.sleepAtEndOfTrack,
  );
}

/// Plays a session as a media service, as NewPipe does: it keeps playing
/// with the screen off or the app in the background, with a notification,
/// lock-screen controls and headset buttons.
///
/// Each track comes from [CacheManager]: the cached file when there is
/// one, else a stream that caches as it plays. When a stream fails, the
/// next way of finding it is tried and playback resumes where it stopped;
/// when every way fails, the session moves on.
class IdrisAudioHandler extends BaseAudioHandler with SeekHandler {
  IdrisAudioHandler({required this.library, required this.cache}) {
    player.playbackEventStream.listen(
      (_) => playbackState.add(_state()),
      onError: (Object e, StackTrace _) => unawaited(_recover(e)),
    );
    player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && !_completing) {
        unawaited(_trackEnded());
      }
    });
    player.durationStream.listen((d) {
      final t = _s.current;
      if (d == null || t == null) return;
      mediaItem.add(mediaItem.value?.copyWith(duration: d));
      if (t.durationMs == 0) unawaited(library.setDuration(t.videoId, d));
    });
  }

  final Library library;
  final CacheManager cache;
  final AudioPlayer player = AudioPlayer();

  final ValueNotifier<SessionState> session = ValueNotifier(
    const SessionState(),
  );

  SessionState get _s => session.value;
  set _s(SessionState v) {
    session.value = v;
    playbackState.add(_state());
  }

  /// The queue as it was before shuffling.
  List<Track>? _unshuffled;
  int _resolver = 0;
  bool _recovering = false;
  bool _completing = false;
  int _openToken = 0;
  Timer? _sleepTimer;

  // --------------------------------------------------------------- session

  /// Plays [queue] from [index]; [source] names where it came from.
  Future<void> startSession(
    List<Track> queue, {
    int index = 0,
    required String source,
    bool shuffle = false,
  }) async {
    if (queue.isEmpty) return;
    final settings = await library.settings();
    var q = queue;
    var i = index.clamp(0, queue.length - 1);
    _unshuffled = null;
    if (shuffle) {
      _unshuffled = queue;
      q = shuffledFrom(queue, i);
      i = 0;
    }
    _s = SessionState(
      queue: q,
      index: i,
      source: source,
      shuffle: shuffle,
      repeatEnd: settings.repeatEnd,
      sleepEndsAt: _s.sleepEndsAt,
      sleepAtEndOfTrack: _s.sleepAtEndOfTrack,
    );
    await _open();
  }

  Future<void> _open({int from = 0, Duration at = Duration.zero}) async {
    final t = _s.current;
    if (t == null) return;
    final token = ++_openToken;
    _s = _s.copyWith(loading: true, problem: () => null);
    mediaItem.add(
      MediaItem(
        id: t.videoId,
        title: t.title,
        artist: t.channel,
        album: _s.source,
        duration: t.durationMs > 0
            ? Duration(milliseconds: t.durationMs)
            : null,
        artUri: thumbnailUrl(t.videoId),
      ),
    );
    try {
      final quality = (await library.settings()).quality;
      final opened = await cache.open(t.videoId, quality, from: from);
      if (token != _openToken) return;
      _resolver = opened.resolver;
      await player.setAudioSource(opened.source, initialPosition: at);
      if (token != _openToken) return;
      _s = _s.copyWith(
        loading: false,
        cached: opened.cached,
        kbps: opened.kbps,
        repeatDone: _s.repeatDone == 0 ? 1 : _s.repeatDone,
      );
      if (at == Duration.zero) {
        unawaited(library.recordPlay(t.videoId));
      }
      unawaited(cache.touch(t.videoId));
      unawaited(player.play());
    } on Object catch (e) {
      if (token != _openToken) return;
      debugPrint('Playback of ${t.videoId} failed: $e');
      await _giveUp();
    }
  }

  /// A stream broke while playing: fetch it another way, carry on from the
  /// same second.
  Future<void> _recover(Object error) async {
    if (_s.current == null || _recovering || _s.loading) return;
    debugPrint('Stream error: $error');
    if (_s.cached || _resolver + 1 >= audioResolvers.length) {
      await _giveUp();
      return;
    }
    _recovering = true;
    _s = _s.copyWith(problem: () => 'Couldn\'t play — trying another source');
    try {
      await _open(from: _resolver + 1, at: player.position);
    } finally {
      _recovering = false;
    }
  }

  /// Can't play the current track: say so briefly, then the next one.
  Future<void> _giveUp() async {
    _s = _s.copyWith(
      loading: false,
      problem: () => 'Couldn\'t play this track — skipping',
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_s.hasNext) {
      _s = _s.copyWith(
        index: _s.index + 1,
        repeatDone: 0,
        repeatTarget: () => null,
      );
      await _open();
    } else {
      await player.stop();
      _s = _s.copyWith(loading: false);
    }
  }

  Future<void> _trackEnded() async {
    _completing = true;
    try {
      final done = _s.repeatDone;
      final next = afterTrackEnds(
        sleepAtEnd: _s.sleepAtEndOfTrack,
        loop: _s.loop,
        repeatTarget: _s.repeatTarget,
        repeatDone: done,
        repeatEnd: _s.repeatEnd,
        hasNext: _s.hasNext,
      );
      switch (next) {
        case AfterTrack.replay:
          if (_s.repeatTarget != null && _s.loop != Loop.one) {
            _s = _s.copyWith(repeatDone: done + 1);
          }
          await player.seek(Duration.zero);
          unawaited(player.play());
          unawaited(library.recordPlay(_s.current!.videoId));
        case AfterTrack.next:
          _s = _s.copyWith(
            index: _s.index + 1,
            repeatTarget: () => null,
            repeatDone: 0,
          );
          await _open();
        case AfterTrack.wrap:
          _s = _s.copyWith(index: 0, repeatTarget: () => null, repeatDone: 0);
          await _open();
        case AfterTrack.stop:
          await player.pause();
          await player.seek(Duration.zero);
          if (_s.sleepAtEndOfTrack) cancelSleep();
          _s = _s.copyWith(repeatTarget: () => null, repeatDone: 1);
      }
    } finally {
      _completing = false;
    }
  }

  // -------------------------------------------------------------- controls

  /// Plays or pauses.
  Future<void> toggle() => player.playing ? pause() : play();

  @override
  Future<void> play() async {
    if (player.processingState == ProcessingState.idle && _s.current != null) {
      await _open();
      return;
    }
    await player.play();
  }

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  /// Back to the start, or (in the first seconds) the track before.
  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3) || _s.index == 0) {
      await player.seek(Duration.zero);
      return;
    }
    _s = _s.copyWith(
      index: _s.index - 1,
      repeatTarget: () => null,
      repeatDone: 0,
    );
    await _open();
  }

  @override
  Future<void> skipToNext() async {
    if (!_s.canSkip) return;
    _s = _s.copyWith(
      index: _s.hasNext ? _s.index + 1 : 0,
      repeatTarget: () => null,
      repeatDone: 0,
    );
    await _open();
  }

  /// Plays the queue item at [index].
  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _s.queue.length) return;
    _s = _s.copyWith(index: index, repeatTarget: () => null, repeatDone: 0);
    await _open();
  }

  /// Ends the session.
  @override
  Future<void> stop() async {
    _openToken++;
    cancelSleep();
    await player.stop();
    cache.playingId = null;
    _unshuffled = null;
    _s = const SessionState();
    await super.stop();
  }

  /// Off → loop the playlist → loop this track → off.
  void cycleLoop() => _s = _s.copyWith(loop: _s.loop.next);

  /// Repeats the current track [times] in all (null turns it off).
  void setRepeat(int? times, {RepeatEnd? end}) => _s = _s.copyWith(
    repeatTarget: () => times,
    repeatDone: times == null ? 1 : (_s.repeatDone == 0 ? 1 : _s.repeatDone),
    repeatEnd: end,
  );

  void setShuffle(bool on) {
    if (on == _s.shuffle || _s.queue.isEmpty) return;
    final current = _s.current!;
    if (on) {
      _unshuffled = _s.queue;
      _s = _s.copyWith(
        queue: shuffledFrom(_s.queue, _s.index),
        index: 0,
        shuffle: true,
      );
    } else {
      final original = _unshuffled ?? _s.queue;
      final i = original.indexWhere((t) => t.videoId == current.videoId);
      _unshuffled = null;
      _s = _s.copyWith(queue: original, index: i < 0 ? 0 : i, shuffle: false);
    }
  }

  /// Plays [track] right after the current one.
  Future<void> playNext(Track track, {String source = ''}) async {
    if (!_s.active) {
      await startSession([track], source: source);
      return;
    }
    final q = [..._s.queue]..insert(_s.index + 1, track);
    _s = _s.copyWith(queue: q);
  }

  /// Adds [track] to the end of the queue.
  Future<void> addToQueue(Track track, {String source = ''}) async {
    if (!_s.active) {
      await startSession([track], source: source);
      return;
    }
    _s = _s.copyWith(queue: [..._s.queue, track]);
  }

  /// Moves an up-next item (indexes count from the item after the current).
  void moveUpNext(int from, int to) {
    final base = _s.index + 1;
    final q = [..._s.queue];
    final item = q.removeAt(base + from);
    q.insert(base + to.clamp(0, q.length - base), item);
    _s = _s.copyWith(queue: q);
  }

  void removeUpNext(int i) {
    final q = [..._s.queue]..removeAt(_s.index + 1 + i);
    _s = _s.copyWith(queue: q);
  }

  void clearUpNext() =>
      _s = _s.copyWith(queue: _s.queue.sublist(0, _s.index + 1));

  // ----------------------------------------------------------- sleep timer

  /// Stops playback after [after], fading out over the last 10 seconds.
  void sleepIn(Duration after) {
    cancelSleep();
    final ends = DateTime.now().add(after);
    _s = _s.copyWith(sleepEndsAt: () => ends, sleepAtEndOfTrack: false);
    _sleepTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final left = ends.difference(DateTime.now());
      if (left <= Duration.zero) {
        unawaited(player.pause());
        unawaited(player.setVolume(1));
        cancelSleep();
      } else if (left < const Duration(seconds: 10)) {
        unawaited(player.setVolume(left.inMilliseconds / 10000));
      }
    });
  }

  /// Stops when the current track ends.
  void sleepAtEndOfTrack() {
    cancelSleep();
    _s = _s.copyWith(sleepAtEndOfTrack: true);
  }

  void cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (player.volume != 1) unawaited(player.setVolume(1));
    if (_s.sleepEndsAt != null || _s.sleepAtEndOfTrack) {
      _s = _s.copyWith(sleepEndsAt: () => null, sleepAtEndOfTrack: false);
    }
  }

  // ------------------------------------------------------- media service

  PlaybackState _state() => PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      if (player.playing) MediaControl.pause else MediaControl.play,
      if (_s.canSkip) MediaControl.skipToNext,
      MediaControl.stop,
    ],
    systemActions: const {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
    },
    androidCompactActionIndices: _s.canSkip ? const [0, 1, 2] : const [0, 1],
    processingState: _s.loading
        ? AudioProcessingState.loading
        : switch (player.processingState) {
            ProcessingState.idle => AudioProcessingState.idle,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          },
    playing: player.playing,
    updatePosition: player.position,
    bufferedPosition: player.bufferedPosition,
    speed: player.speed,
    queueIndex: _s.index,
  );
}

/// Starts the media service (Android only) and returns its handler; other
/// platforms and tests get a plain handler.
Future<IdrisAudioHandler> initAudio({
  required Library library,
  required CacheManager cache,
}) async {
  IdrisAudioHandler make() => IdrisAudioHandler(library: library, cache: cache);
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return make();
  try {
    return await AudioService.init(
      builder: make,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.isg32.idris.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationIcon: 'drawable/ic_notify_playback',
        androidStopForegroundOnPause: true,
      ),
    );
  } on Object catch (e) {
    debugPrint('Media service unavailable: $e');
    return make();
  }
}
