import 'dart:async';
import 'dart:convert';

import 'package:courses_sse_client/courses_sse_client.dart' show SseClient;
import 'package:http/http.dart' as http;
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

const host = 'localhost:8067';
const sse_url = 'http://$host/sync';

Future<Object> fetchData(String uri) async {
  var response = await http.get(Uri.http(host, uri));
  if (response.statusCode == 200) {
    return json.decode(response.body) as Object;
  } else {
    throw Exception('Failed to fetch URI');
  }
}

void main() {
  test('Connexion', () async {
    var data = <String>[];
    var client = SseClient.fromUrl(sse_url);
    await client.onConnected;
    client.stream.listen((event) => data.add(event), cancelOnError: true);
    var client2 = SseClient.fromUrl(sse_url);
    await client2.onConnected;
    client2.stream.listen((event) => data.add(event), cancelOnError: true);
    client.close();
    client2.close();
  });

  test('Déconnexion client', () async {
    var data = <String>[];
    var client = SseClient.fromUrl(sse_url);
    await client.onConnected;
    client.stream.listen(
      (event) => data.add(event),
      cancelOnError: true,
    );
    await Future.delayed(Duration(seconds: 2));
    client.close();
    await Future.delayed(Duration(seconds: 2));
  });

  test('Arrêt manuel du serveur', () async {
    var data = <String>[];
    var closed = Completer<String>();
    var client = SseClient.fromUrl(sse_url);
    await client.onConnected;
    client.stream.listen(
      (event) => data.add(event),
      cancelOnError: true,
      onDone: () {
        if (!closed.isCompleted) closed.complete('Connexion interrompue');
      },
    );
    unawaited(Future.delayed(Duration(seconds: 10))
        .whenComplete(() => closed.complete('Timeout expiré')));
    print(await closed.future);
    client.close();
  });
}
