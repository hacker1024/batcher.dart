# Batcher

A robust future batching solution.

## Usage

### Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  ...
  batcher: ^0.1.0-nullsafety.1
```

And import it:

```dart
import 'package:batcher/batcher.dart';
```

### Batching

A `FutureBatcher` takes an `Iterable` containing _generator functions_. A
generator function creates a future for the batcher when it needs it. Say, for
example, you want to download a list of files in batches with `package:http`:

```dart
// A predetermined list of file URIs.
final fileUris = <Uri>[ /*...*/];

// Use a single client to speed up mass connections.
final client = http.Client();

// Create a list of generators.
final downloadFutureGenerators = [
  for (final uri in fileUris)
        () => http.get(uri).then((response) => response.body),
];
```

Note this is not a list of futures; it's a list of anonymous functions that
_create_ futures. This allows a batcher to make the HTTP requests in batches.

Generators can be added to a batcher at any time. If any
threads are available, they will start to be called right away; otherwise, they
will stay in the queue until a thread is ready.

As well as requiring future generators, a thread count must also be specified.
This thread count is the maximum number of futures that will be resolving at any
time. This thread count can change at any time; the new number will be used after
excess pending operations complete.

With these two things, futures can be batched in a few different ways:

#### Future-based batching

In this way, queued results are delivered via futures returned by `get` functions.

```dart
// Create a batcher with 16 threads.
final batcher = FutureBatcher<String>(16);

// Add a single generator to the queue.
final Future<String> future =
    batcher.get(() => http.get(uri).then((response) => response.body));

// Or, add multiple generators to the queue.
final List<Future<String>> futures = batcher.getAll(generators);

// The following can also be used to create a batcher and call getAll in one line.
final futures = generators.batch(16);
```

#### Stream-based batching
If you need to get results from completed futures, but you don't care which
result came from which generator, this is an appropriate method. It's more
optimised than future-based batching for large amounts of work.

This method utilises the `StreamingFutureBatcher` class.

Say, for example, you wish to pull a list of random fake names from an API,
with the `getRandomName` function that returns a `Future<String>`:

```dart
// Create a list of generators.
final generators = List.filled(100, () => getRandomName());

// Create a streaming batcher from the generators with 16 threads.
final batcher = StreamingFutureBatcher.from(generators, 16);

// Or, use the extension function:
final batcher = generators.streamBatch(16);

// The results stream can be used like any other.
await for (final name in batcher.results) {
  print(name);
}
```

By default, the batcher will close down after all pending generators are
resolved. This can be changed with a constructor argument (or by using the
default constructor) to get behaviour that's closer to `FutureBatcher`.

Note that `addAll` is used here; while `getAll` also works, it adds overhead by
dealing with return values that we don't need.

```dart
// Create a streaming batcher with 16 threads.
final batcher = StreamingFutureBatcher(16);

// Add the generators.
batcher.addAll(generators);

// Do stuff (like adding more)...
...

// Close when done.
batcher.close();
```

#### Simple batching

This is the way to go if you don't need to `await` anything or remember which
results came from which generator.

This is useful, for example, in I/O operations like writing files to a cache
service where you don't care if they finish completing:

```dart
// File paths and contents.
final paths = <String>[/*...*/];
final contents = <String>[/*...*/];

// Map the file data to generators.
final generators = List.generate(
  paths.length,
      (index) => () => File(paths[index]).writeAsString(contents[index]),
);

// Create a batcher with 16 threads.
final batcher = FutureBatcher<void>(16);

// Add the generators.
batcher.addAll(generators);
```

## FAQ

- Q: What can this be useful for?  
  A:
  - Accelerating network requests (one at a time, you can be limited by server speeds; all at once with `Future.wait`, you can be blocked by the platform or server)
  - Filesystem I/O, where there are open file limits


- Q: How does this compare to [`package:batching_future`](https://pub.dev/packages/batching_future)?  
  A: Both packages can do similar things, but they're made for different usecases. `batching_future`
  is great for unpredictable, rapid API calls, with caching support and time-based batching.
  This package is made for predictable, ongoing batches, taking fixed-sized lists of generators.