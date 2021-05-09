import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:courses_sse_client/courses_sse_client.dart' show SseClient;
import 'package:http/http.dart' as http;
import 'package:pedantic/pedantic.dart';
import 'package:restserver/courses_api.dart';
import 'package:restserver/courses_db_storage.dart';
import 'package:restserver/courses_sse.dart';
import 'package:restserver/mapdb.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:test/test.dart';

void main() async {
  await local_server();

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
    var closed = Completer<String>();
    await client.onConnected;
    client.stream.listen(
      (event) => data.add(event),
      cancelOnError: true,
      onDone: () {
        if (!closed.isCompleted) closed.complete('CLOSED');
      },
    );
    await Future.delayed(Duration(seconds: 1));
    client.close();
    await Future.delayed(Duration(seconds: 1));
    assert(closed.isCompleted && await closed.future == 'CLOSED');
  });

  test('Arrêt du serveur SSE', () async {
    var data = <String>[];
    var closed = Completer<String>();
    var client = SseClient.fromUrl(sse_url);
    await client.onConnected;
    client.stream.listen(
      (event) => data.add(event),
      cancelOnError: true,
      onDone: () {
        if (!closed.isCompleted) closed.complete('SHUTDOWN');
      },
    );
    // Timeout de 10 secondes qui ne devrait pas arriver
    unawaited(Future.delayed(Duration(seconds: 10))
        .whenComplete(() => closed.complete('TIMEOUT')));

    // Attend deux secondes puis ferme le serveur SSE
    await Future.delayed(Duration(seconds: 2));
    sse_server.shutdown();

    assert(await closed.future == 'SHUTDOWN');
    client.close();
  });
}

const host = 'localhost';
const host_url = '$host:$port';
const port = '8002';

const sse_url = 'http://$host_url/sync';

Future<Object> fetchData(String uri) async {
  var response = await http.get(Uri.http(host, uri));
  if (response.statusCode == 200) {
    return json.decode(response.body) as Object;
  } else {
    throw Exception('Failed to fetch URI');
  }
}

var sse_server;

Future<HttpServer> local_server() async {
  db = CacheDb(DbFileReadOnlyAdaptor(''));
  await db.isLoaded;

  final courses_api = Router();
  courses_api.mount('/courses/', CoursesApi().router);

  sse_server = SseHandler(Uri.parse('/sync'));
  courses_sse.listen(sse_server);

  final cascade =
      Cascade().add(courses_api).add(courses_sse).add(sse_server.handler);

  final pipeline =
      const Pipeline().addMiddleware(logRequests()).addHandler(cascade.handler);

  final server = await io.serve(pipeline, host, int.parse(port));

  return server;
}
