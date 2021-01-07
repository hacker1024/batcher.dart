import 'package:batcher/src/future_batcher.dart';
import 'package:batcher/src/streaming_future_batcher.dart';

extension BatcherX<T> on Iterable<BatchedFutureGenerator<T>> {
  /// Creates a [FutureBatcher] with the given [threadCount] and returns the
  /// result of [FutureBatcher.getAll].
  ///
  /// If you need to do this more that once, create a batcher manually instead.
  List<Future<T>> batch(int threadCount) =>
      FutureBatcher<T>(threadCount).getAll(this);

  /// Like [Future.wait], but in batches with a maximum [threadCount] instead of
  /// all at once.
  Future<List<T>> batchWait(
    int threadCount, {
    bool eagerError = false,
    void Function(T successValue)? cleanUp,
  }) =>
      Future.wait(
        batch(threadCount),
        eagerError: eagerError,
        cleanUp: cleanUp,
      );

  /// Creates a stream of batched futures from this collection with the given
  /// [threadCount].
  Stream<T> streamBatch(int threadCount) =>
      StreamingFutureBatcher.from(this, threadCount, closeWhenIdle: true)
          .results;
}
