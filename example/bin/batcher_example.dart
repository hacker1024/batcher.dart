import 'dart:convert';

import 'package:batcher/batcher.dart';
import 'package:http/http.dart';

void main() async {
  // Create a client for HTTP requests.
  final client = Client();

  // Generate a list of [BatchedFutureGenerator]s to generate futures that
  // fetch a random country with [_getCountries].
  //
  // A small delay is added to make the batching effect more obvious.
  final generators = List.filled(
    12,
    () => Future.delayed(const Duration(milliseconds: 500))
        .then((_) => _getCountry(client)),
    growable: false,
  );

  // Use a thread count of 3.
  const threadCount = 3;

  // -- Complete the generators in a batch --
  print('Fetching countries...');
  // Generate a list of batched futures.
  final futures1 = generators.batch(threadCount);
  // Await and print them.
  futures1.forEach((future) async => print(await future));
  // Wait for everything to finish before continuing.
  await Future.wait(futures1);
  print('Done.\n');

  // -- Add futures later on --
  print('Fetching two lots of countries...');
  final batcher1 = FutureBatcher(threadCount);
  // Add, print, and await one lot of countries.
  print('First lot...');
  final lot1 = batcher1.getAll(generators);
  lot1.forEach((future) async => print(await future));
  await Future.wait(lot1);
  // Wait for two seconds.
  await Future.delayed(const Duration(seconds: 2));
  print('\nSecond lot...');
  // Do it again!
  final lot2 = batcher1.getAll(generators);
  lot2.forEach((future) async => print(await future));
  await Future.wait(lot2);
  print('Done.\n');

  // // -- Change the thread count --
  // Start a batch (with more generators to show the effects).
  print('Going to change the thread count...');
  final batcher2 = FutureBatcher(threadCount);
  final futures2 = batcher2.getAll(generators + generators);
  // Start printing results.
  futures2.forEach((future) async => print(await future));
  // Two seconds in, change the thread count!
  await Future.delayed(const Duration(seconds: 2));
  batcher2.threadCount = 6;
  print('Changed from $threadCount to 6!');
  // Wait for everything to complete.
  await Future.wait(futures2);
  print('Done.\n');

  // -- Stream results --
  print('Streaming countries...');
  final stream = generators.streamBatch(threadCount);
  await for (final country in stream) {
    print(country);
  }

  // Clean up.
  client.close();
}

final apiUri = Uri(
  scheme: 'http',
  host: 'names.drycodes.com',
  path: '1',
  queryParameters: const {
    'combine': '1',
    'nameOptions': 'countries',
  },
);

Future<String> _getCountry(Client client) async =>
    jsonDecode((await client.get(apiUri)).body)[0];

// Other (rate limited) APIs
/*
final apiUri = Uri(scheme: 'https', host: 'api.namefake.com');

Future<String> _getName(Client client) async =>
    jsonDecode((await client.get(apiUri)).body)['name'];

final apiUri = Uri.parse('https://randomuser.me/api/1.3/');
*/
/*
Future<String> _getName(Client client) async {
  final List<dynamic>? userListJson =
      jsonDecode((await client.get(apiUri)).body)['results'];
  final nameJson = userListJson?[0]['name'];
  return '${nameJson?['title']} ${nameJson?['first']} ${nameJson?['last']}';
}
*/
