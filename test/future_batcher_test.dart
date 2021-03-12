import 'dart:async';
import 'dart:math';

import 'package:batcher/batcher.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

// Parameters for batch tests.
const batchStartSize = 0;
const batchEndSize = 128;
const batchSizeStep = 5;
const batchStartThreadCount = 1;
const batchEndThreadCount = 128;
const batchThreadCountStep = 5;

// List generators using various FutureBatcher implementations.
typedef BatchToList<T> = Future<List<T>> Function(
  int threadCount,
  Iterable<BatchedFutureGenerator<T>> generators,
);

Future<List<T>> awaitToList<T>(
  int threadCount,
  Iterable<BatchedFutureGenerator<T>> generators,
) async =>
    [
      for (final future in FutureBatcher<T>(threadCount).getAll(generators))
        await future
    ];

Future<List<T>> streamToList<T>(
  int threadCount,
  Iterable<BatchedFutureGenerator<T>> generators,
) =>
    StreamingFutureBatcher.from(generators, threadCount).results.toList();

/// https://github.com/dart-lang/sdk/issues/39305#issuecomment-581013757
final Matcher throwsAssertionError = throwsA(isA<AssertionError>());

void main() {
  // Tests that a list of generators resolves as expected.
  group(
    'Basic input/output',
    () {
      Future<void> testInputOutput(
        int size,
        int threadCount,
        BatchToList batch,
      ) async {
        final valuesToGenerate = List.generate(size, (index) => index);
        final generators = valuesToGenerate.map((i) => () async => i);

        final output = await batch(threadCount, generators);

        expect(output..sort(), equals(valuesToGenerate..sort()));
      }

      Future<void> batchTestInputOutput(
        int startSize,
        int endSize,
        int sizeStep,
        int startThreadCount,
        int endThreadCount,
        int threadCountStep,
        BatchToList batch,
      ) async {
        for (var size = startSize; size <= endSize; size += sizeStep) {
          for (var threadCount = startThreadCount;
              threadCount <= endThreadCount;
              threadCount += threadCountStep) {
            await testInputOutput(size, threadCount, batch);
          }
        }
      }

      test(
        'Test awaited output',
        () async {
          await batchTestInputOutput(
            batchStartSize,
            batchEndSize,
            batchSizeStep,
            batchStartThreadCount,
            batchEndThreadCount,
            batchThreadCountStep,
            awaitToList,
          );
        },
      );

      test(
        'Test streamed output',
        () async {
          await batchTestInputOutput(
            batchStartSize,
            batchEndSize,
            batchSizeStep,
            batchStartThreadCount,
            batchEndThreadCount,
            batchThreadCountStep,
            streamToList,
          );
        },
      );
    },
  );

  test(
    'Using thread counts of less than one should raise an AssertionError',
    () {
      expect(() => FutureBatcher(0), throwsAssertionError);
      expect(() => FutureBatcher(-1), throwsAssertionError);
      expect(() => FutureBatcher(1).threadCount = 0, throwsAssertionError);
      expect(() => FutureBatcher(1).threadCount = -1, throwsAssertionError);

      expect(() => StreamingFutureBatcher(0), throwsAssertionError);
      expect(() => StreamingFutureBatcher(-1), throwsAssertionError);
      expect(() => StreamingFutureBatcher(1).threadCount = 0,
          throwsAssertionError);
      expect(() => StreamingFutureBatcher(1).threadCount = -1,
          throwsAssertionError);
      expect(
          () => StreamingFutureBatcher.from(const [], 0), throwsAssertionError);
      expect(() => StreamingFutureBatcher.from(const [], -1),
          throwsAssertionError);
    },
  );

  group(
    'Thread count changes',
    () {
      Future<void> testThreadCountChange(
        int size,
        int initialThreadCount,
        int nextThreadCount,
      ) async {
        final valuesToGenerate = List.generate(size, (index) => index);
        final output = <int>[];
        final generators = valuesToGenerate.map((i) => () async => i);

        final threadCountChangePoint = size ~/ 2;
        final batcher = FutureBatcher<int>(initialThreadCount);
        for (final future in batcher.getAll(generators)) {
          final result = await future;
          if (result == threadCountChangePoint) {
            batcher.threadCount = nextThreadCount;
          }
          output.add(result);
        }
        expect(output..sort(), equals(valuesToGenerate..sort()));
      }

      Future<void> batchTestThreadCountChange(
        int startSize,
        int endSize,
        int sizeStep,
        int startInitialThreadCount,
        int endInitialThreadCount,
        int initialThreadCountStep,
        double nextThreadCountScaleFactor,
      ) async {
        for (var size = startSize; size <= endSize; size += sizeStep) {
          for (var threadCount = startInitialThreadCount;
              threadCount <= endInitialThreadCount;
              threadCount += initialThreadCountStep) {
            await testThreadCountChange(
              size,
              threadCount,
              (threadCount * nextThreadCountScaleFactor).round(),
            );
          }
        }
      }

      group(
        'Lowering the thread count should not cause a change in results',
        () {
          test(
            '1:0.8',
            () async {
              await batchTestThreadCountChange(
                batchStartSize,
                batchEndSize,
                batchSizeStep,
                batchStartThreadCount,
                batchEndThreadCount,
                batchThreadCountStep,
                0.8,
              );
            },
          );

          test(
            '1:0.4',
            () async {
              await batchTestThreadCountChange(
                batchStartSize,
                batchEndSize,
                batchSizeStep,
                max(batchStartThreadCount,
                    2) /* Using a value of one here results in a decrease to zero. */,
                batchEndThreadCount,
                batchThreadCountStep,
                0.4,
              );
            },
          );
        },
      );

      group(
        'Increasing the thread count should not cause a change in results',
        () {
          test(
            '1:1.8',
            () async {
              await batchTestThreadCountChange(
                batchStartSize,
                batchEndSize,
                batchSizeStep,
                batchStartThreadCount,
                batchEndThreadCount,
                batchThreadCountStep,
                1.8,
              );
            },
          );

          test(
            '1:1.4',
            () async {
              await batchTestThreadCountChange(
                batchStartSize,
                batchEndSize,
                batchSizeStep,
                batchStartThreadCount,
                batchEndThreadCount,
                batchThreadCountStep,
                1.4,
              );
            },
          );
        },
      );
    },
  );

  group(
    'Errors',
    () {
      test(
        'Errors should pass through to returned futures in await calls',
        () async {
          Future<void> run(FutureBatcher batcher) async {
            expect(
              batcher.get(() async => throw const FormatException()),
              throwsFormatException,
            );
          }

          await run(FutureBatcher(1));
          await run(FutureBatcher(8));
          await run(StreamingFutureBatcher(1));
          await run(StreamingFutureBatcher(8));
        },
      );

      group(
        'Streamed batchers should also output errors to their streams',
        () {
          test(
            'add',
            () async {
              Future<void> run(StreamingFutureBatcher batcher) async {
                batcher.add(() async => throw const FormatException());
                expect(
                  batcher.results,
                  emitsError(isFormatException),
                );
              }

              await run(StreamingFutureBatcher(1));
              await run(StreamingFutureBatcher(8));
            },
          );

          test(
            'wait',
            () async {
              Future<void> run(StreamingFutureBatcher batcher) async {
                unawaited(
                    batcher.get(() async => throw const FormatException()));
                expect(
                  batcher.results,
                  emitsError(isFormatException),
                );
              }

              await run(StreamingFutureBatcher(1));
              await run(StreamingFutureBatcher(8));
            },
          );
        },
      );
    },
  );

  // TODO tests for ensuring thread counts are correct, queue additions
}
