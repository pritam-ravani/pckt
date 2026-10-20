import 'dart:async';
import 'dart:collection';

import '../llm_client.dart';

/// Who is waiting for the on-device model. The phone runs one generation at
/// a time, so the user's own question must never queue behind batch work.
enum OnDevicePriority { interactive, background }

/// Thrown into a background job whose generation was stopped so an
/// interactive request could run. The job should stop and resume later.
class OnDevicePreempted extends LlmException {
  const OnDevicePreempted() : super(LlmErrorKind.timeout, 'Paused for a question in Ask');
}

/// Handed to a running job: lets the scheduler stop it.
class OnDeviceRun {
  OnDeviceRun._(this.priority);
  final OnDevicePriority priority;
  bool _preempted = false;
  FutureOr<void> Function()? _onPreempt;

  bool get preempted => _preempted;

  /// [stop] is called (once) if an interactive request arrives while this
  /// background run holds the model — e.g. `chat.stopGeneration()`.
  void onPreempt(FutureOr<void> Function()? stop) {
    _onPreempt = stop;
    if (_preempted && stop != null) unawaited(Future.sync(stop).catchError((_) {}));
  }

  void _preempt() {
    if (_preempted || priority != OnDevicePriority.background) return;
    _preempted = true;
    final stop = _onPreempt;
    if (stop != null) unawaited(Future.sync(stop).catchError((_) {}));
  }
}

class _Job {
  _Job(this.priority, this.seq);
  final OnDevicePriority priority;
  final int seq;
  final ready = Completer<OnDeviceRun>();
}

/// Single-slot, priority-aware queue for the on-device model.
///
/// * One job runs at a time (LiteRT has one live conversation per engine).
/// * Interactive jobs jump ahead of every waiting background job.
/// * An interactive job arriving while a background job runs preempts it
///   (its [OnDeviceRun.onPreempt] hook stops generation); background work
///   waits until no interactive job is queued or running.
/// * After [idleAfter] with nothing queued, [onIdle] fires (used to unload
///   the model and free ~2–3 GB of RAM).
class OnDeviceScheduler {
  OnDeviceScheduler({this.idleAfter = const Duration(minutes: 3), this.onIdle});

  final Duration idleAfter;
  FutureOr<void> Function()? onIdle;

  final _waiting = SplayTreeSet<_Job>(
    (a, b) => a.priority != b.priority ? a.priority.index - b.priority.index : a.seq - b.seq,
  );
  OnDeviceRun? _running;
  var _seq = 0;
  Timer? _idleTimer;
  DateTime _lastActivity = DateTime.now();
  final _idleWaiters = <Completer<void>>[];

  bool get busy => _running != null || _waiting.isNotEmpty;

  /// An Ask request is running or waiting — background work should yield.
  bool get interactivePending =>
      _running?.priority == OnDevicePriority.interactive ||
      _waiting.any((j) => j.priority == OnDevicePriority.interactive);

  DateTime get lastActivity => _lastActivity;

  Future<T> run<T>(OnDevicePriority priority, Future<T> Function(OnDeviceRun run) work) async {
    _idleTimer?.cancel();
    final job = _Job(priority, _seq++);
    _waiting.add(job);
    if (priority == OnDevicePriority.interactive) _running?._preempt();
    _pump();
    final run = await job.ready.future;
    try {
      if (run.preempted) throw const OnDevicePreempted();
      return await work(run);
    } finally {
      _running = null;
      _lastActivity = DateTime.now();
      _pump();
    }
  }

  void _pump() {
    if (_running != null) return;
    if (_waiting.isEmpty) {
      _armIdle();
      return;
    }
    final next = _waiting.first;
    _waiting.remove(next);
    final run = _running = OnDeviceRun._(next.priority);
    // A background job that reaches the front while an interactive one is
    // queued behind it can't happen (ordering), but one queued earlier may
    // still be preempted by an interactive request that arrives later.
    next.ready.complete(run);
  }

  void _armIdle() {
    _idleTimer?.cancel();
    for (final w in _idleWaiters) {
      if (!w.isCompleted) w.complete();
    }
    _idleWaiters.clear();
    final cb = onIdle;
    if (cb == null) return;
    _idleTimer = Timer(idleAfter, () {
      if (!busy) unawaited(Future.sync(cb).catchError((_) {}));
    });
  }

  /// Completes once nothing has used the model for [quiet].
  Future<void> whenQuiet(Duration quiet) async {
    while (true) {
      if (busy) {
        final c = Completer<void>();
        _idleWaiters.add(c);
        await c.future;
        continue;
      }
      final since = DateTime.now().difference(_lastActivity);
      if (since >= quiet) return;
      await Future<void>.delayed(quiet - since);
    }
  }

  void dispose() {
    _idleTimer?.cancel();
  }
}

/// How long one generation may take before we give up. Bigger models are
/// slower per token on the same phone; batch jobs send more text and may
/// take longer, but are never what the user is waiting on.
Duration onDeviceTurnTimeout({required int modelBytes, required OnDevicePriority priority}) {
  final gb = modelBytes / (1024 * 1024 * 1024);
  final interactive = Duration(seconds: (60 + 60 * gb).round());
  return priority == OnDevicePriority.interactive ? interactive : interactive * 2;
}
