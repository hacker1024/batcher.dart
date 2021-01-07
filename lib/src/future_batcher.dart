import 'dart:async';
import 'dart:collection';
import 'dart:math';

/// A batched future generator creates a future, and is called when the future
/// is due to be resolved.
typedef BatchedFutureGenerator<T> = Future<T> Function();

/// An object that batches futures.
class FutureBatcher<T> {
  /// The queue used internally to queue future generators.
  final _queue = Queue<_QueueItem<T>>();

  /// A list of running "threads".
  final List<Future<void>> _threads = [];

  /// See [threadCount].
  int _threadCount;

  FutureBatcher(int threadCount)
      : assert(threadCount > 0, 'At least one thread must be provided!'),
        _threadCount = threadCount;

  /// The maximum amount of "thread"s to use to complete the futures in batches.
  ///
  /// Note that these "threads" are not actual Dart threads; they run in the
  /// main isolate/event loop.
  int get threadCount => _threadCount;

  /// Sets the [threadCount].
  ///
  /// This must be greater than zero.
  /// If the count is reduced, running threads will exit after they finish
  /// resolving their current futures until the new thread count is met.
  set threadCount(int newThreadCount) {
    if (newThreadCount == _threadCount) return;

    assert(newThreadCount > 0, 'At least one thread must be provided!');
    _threadCount = newThreadCount;

    // Create additional threads if the new value is higher than the existing
    // amount. If it's not, just assign it and the next threads to finish
    // tasks will exit until the running amount is correct.
    if (_threadCount > _threads.length) {
      _createMissingThreads();
    }
  }

  /// The current length of the future queue.
  int get queueLength => _queue.length;

  /// True if the queue is empty.
  bool get queueIsEmpty => _queue.isEmpty;

  /// True if the batcher is in an idle state (no threads are running).
  bool get isIdle => _threads.isEmpty;

  /// Creates a "thread" that resolves futures from the [_queue].
  ///
  /// If the queue is empty, or if the amount of running threads is greater than
  /// the [threadCount] and the thread is the last thread, the "thread" will
  /// exit (the stream will close) after it finishes resolving its current
  /// future.
  Future<void> _createThread(bool Function() isLast) async {
    while (
        _queue.isNotEmpty && (_threads.length <= _threadCount || !isLast())) {
      final item = _queue.removeFirst();
      final future = item.generator();
      item.completer?.complete(future);
      try {
        await future;
      } catch (_) {
        // https://github.com/dart-lang/sdk/issues/29361#issuecomment-756530265
      }
    }
  }

  /// Adds a thread to [_threads], and removes it when
  /// it's complete.
  void _addThread() {
    late final Future<void> thread;
    thread = _createThread(() => identical(_threads.last, thread));
    _threads.add(
      thread
        ..then((_) {
          _threads.remove(thread);
        }),
    );
  }

  /// Checks if more threads should be made given the queue size and running
  /// thread count, and creates them if necessary.
  void _createMissingThreads() {
    // The amount of threads needed is the queue length, or the maximum
    // thread count if the queue length is bigger than it.
    final requiredThreadCount = min(_threadCount, _queue.length);
    for (var i = _threads.length; i < requiredThreadCount; ++i) {
      _addThread();
    }
  }

  /// Adds a future generator to the queue.
  ///
  /// If you care about the future's result, use [get]. If you don't care,
  /// this function is more optimised.
  void add(BatchedFutureGenerator<T> generator) {
    _queue.add(_QueueItem(generator, null));
    _createMissingThreads();
  }

  /// Adds several future generators to the queue.
  ///
  /// If you care about the results, use [getAll]. If you don't care, this
  /// function is more optimised.
  void addAll(Iterable<BatchedFutureGenerator<T>> generators) {
    _queue.addAll(
        [for (final generator in generators) _QueueItem(generator, null)]);
    _createMissingThreads();
  }

  /// Adds a future generator to the queue and completes with its result or
  /// error.
  ///
  /// If you don't care about the result, use [add] for better
  /// performance.
  Future<T> get(BatchedFutureGenerator<T> generator) {
    final completer = Completer<T>();
    _queue.add(_QueueItem(generator, completer));
    _createMissingThreads();
    return completer.future;
  }

  /// Adds several future generators to the queue and returns a list of futures
  /// that complete with their results or errors.
  ///
  /// If you don't care about the results, use [addAll] for better
  /// performance.
  List<Future<T>> getAll(Iterable<BatchedFutureGenerator<T>> generators) {
    final items = [
      for (final generator in generators) _QueueItem<T>(generator, Completer())
    ];
    _queue.addAll(items);
    _createMissingThreads();
    return [for (final item in items) item.completer!.future];
  }
}

class _QueueItem<T> {
  final BatchedFutureGenerator<T> generator;
  final Completer<T>? completer;

  const _QueueItem(this.generator, this.completer);
}
