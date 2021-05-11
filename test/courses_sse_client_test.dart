import 'dart:async';
import 'dart:io';

import 'package:courses_sse_client/courses_sse_client.dart' show SseClient;
import 'package:restserver/courses_db_storage.dart';
import 'package:restserver/courses_sse.dart';
import 'package:restserver/mapdb.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
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

  test(
    'Déconnexion client',
    () async {
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
      // Attend deux secondes puis ferme le client
      await Future.delayed(Duration(seconds: 2));
      client.close();
      // Attend que le client soit averti de la fermeture du stream SSE
      assert(await closed.future == 'CLOSED');
    },
    timeout: Timeout(Duration(seconds: 4)),
  );

  test(
    'Arrêt du serveur SSE',
    () async {
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
      // Attend deux secondes puis ferme le serveur
      await Future.delayed(Duration(seconds: 2));
      sse_server.shutdown();
      // Attend que le client soit averti de la fermeture du stream SSE
      assert(await closed.future == 'SHUTDOWN');
      client.close();
    },
    timeout: Timeout(Duration(seconds: 4)),
  );
}

const host = 'localhost';
const host_url = '$host:$port';
const port = '8002';
const sse_url = 'http://$host_url/sync';

var sse_server = SseHandler(Uri.parse('/sync'));

class DbEmptyAdaptor implements DbAdaptor {
  @override
  Future<Map<String, dynamic>> loadAll() async => {};

  @override
  void update(String collection, String ID, Map<String, dynamic> value) {}
}

Future<HttpServer> local_server() async {
  db = CacheDb(DbEmptyAdaptor());
  await db.isLoaded;

  //sse_server = SseHandler(Uri.parse('/sync'));
  courses_sse.listen(sse_server);

  final cascade = Cascade().add(courses_sse).add(sse_server.handler);
  final pipeline = const Pipeline().addHandler(cascade.handler);

  return io.serve(pipeline, host, int.parse(port));
}
