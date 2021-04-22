import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:courses_sse_client/courses_sse_client.dart' show SseClient;

const host = 'localhost:8067';

Future<Object> fetchData(String uri) async {
  var response = await http.get(Uri.http(host, uri));
  if (response.statusCode == 200) {
    return json.decode(response.body) as Object;
  } else {
    throw Exception('Failed to fetch URI');
  }
}

void main() {
  test('SseClient', () async {
    const sse_url = 'http://$host/sync';
    var client;
    var data = <String>[];
    try {
      client = SseClient.fromUrl(sse_url)
        ..stream.listen((event) => data.add(event), cancelOnError: true);
      await client.onConnected;
      client.close();
      var client2 = SseClient.fromUrl(sse_url)
        ..stream.listen((event) => data.add(event), cancelOnError: true);
      assert(client != client2);
    } on Exception {
      print('Connexion impossible');
      assert(false);
    }
  });
}
