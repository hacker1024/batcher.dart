import 'dart:async';

import 'package:batcher/src/future_batcher.dart';

/// A variant of [FutureBatcher] that outputs results to a broadcast
/// [Stream] as well as returned [Future]s.
///
/// It fully implements [Sink].
class StreamingFutureBatcher<T> extends FutureBatcher<T>
    implements Sink<BatchedFutureGenerator<T>> {
  /// The [results] controller.
  final _controller = StreamController<T>.broadcast();

  /// True if the batcher should close when it becomes idle.
  bool _closeWhenIdle;

  /// A counter for the number of results broadcasted.
  int _resultCount = 0;

  int _totalResultCount = 0;

  StreamingFutureBatcher(int threadCount)
      : _closeWhenIdle = false,
        super(threadCount);

  /// Creates a batcher from an iterable of generators.
  ///
  /// Creating a batcher in this way allows the stream to close automatically
  /// when everything has completed. This behaviour is set with [closeWhenIdle].
  /// When [closeWhenIdle] is true, this can be a drop-in replacement for
  /// [Stream.fromFutures).
  ///
  /// [closeWhenIdle] can also be changed at any point before closing.
  StreamingFutureBatcher.from(
    Iterable<BatchedFutureGenerator<T>> generators,
    int threadCount, {
    bool closeWhenIdle = true,
  })  : _closeWhenIdle = closeWhenIdle,
        super(threadCount) {
    // Add the initial generators.
    addAll(generators);
    // Close immediately if there were no initial generators and closeWhenIdle
    // is true.
    if (_totalResultCount == 0 && closeWhenIdle) close();
  }

  /// The stream of results.
  Stream<T> get results => _controller.stream;

  /// The number of results resolved so far.
  int get resultCount => _resultCount;

  /// Whether the batcher will close once idle or not.
  bool get closeWhenIdle => _closeWhenIdle;

  set closeWhenIdle(bool value) {
    if (value && _resultCount == _totalResultCount) close();
    _closeWhenIdle = value;
  }

  @override
  void add(BatchedFutureGenerator<T> generator) {
    super.add(_register(generator));
  }

  @override
  void addAll(Iterable<BatchedFutureGenerator<T>> generators) {
    super.addAll(_registerAll(generators));
  }

  @override
  Future<T> get(BatchedFutureGenerator<T> generator) {
    return super.get(_register(generator));
  }

  @override
  List<Future<T>> getAll(Iterable<BatchedFutureGenerator<T>> generators) {
    return super.getAll(_registerAll(generators));
  }

  @override
  void close() {
    _controller.close();
  }

  BatchedFutureGenerator<T> _register(BatchedFutureGenerator<T> generator) {
    ++_totalResultCount;
    return () => generator()
      ..then(_controller.add, onError: _controller.addError)
          .then((_) => _notifyNewResult());
  }

  List<BatchedFutureGenerator<T>> _registerAll(
    Iterable<BatchedFutureGenerator<T>> generators,
  ) =>
      [for (final generator in generators) _register(generator)];

  void _notifyNewResult() {
    if (++_resultCount == _totalResultCount && closeWhenIdle) {
      close();
    }
  }
}
