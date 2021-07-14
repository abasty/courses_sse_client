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
  var ngrok = Platform.environment['NGROK'];
  dynamic ngrok_skipped = ngrok != null ? false : 'No NGROK environment';

  await local_server();

  test('Connexion', () async {
    var data = <String>[];
    var client = SseClient.fromUriAndPath(uri, path);
    await client.onConnected;
    client.stream.listen((event) => data.add(event), cancelOnError: true);
    var client2 = SseClient.fromUriAndPath(uri, path);
    await client2.onConnected;
    client2.stream.listen((event) => data.add(event), cancelOnError: true);
    client.close();
    client2.close();
  });

  test(
    'Connexion ngrok',
    // TODO: Added zoned? Or Zoned on/sync request?
    // <https://dart.dev/articles/archive/zones#handling-asynchronous-errors>
    () async {
      var data = <String>[];
      var uri_ngrok = Uri(
        scheme: 'https',
        host: ngrok! + '.eu.ngrok.io',
      );
      SseClient? client;
      SseClient? client2;

      try {
        client = SseClient.fromUriAndPath(uri_ngrok, path);
        await client.onConnected;
        client.stream.listen((event) => data.add(event), cancelOnError: true);
      } catch (e) {
        assert(false, 'Erreur de connexion');
      }

      try {
        client2 = SseClient.fromUriAndPath(uri_ngrok, path);
        await client2.onConnected;
        client2.stream.listen((event) => data.add(event), cancelOnError: true);
      } catch (e) {
        assert(false, 'Erreur de connexion');
      }

      // Attend deux secondes puis ferme les clients
      await Future.delayed(Duration(seconds: 2));
      try {
        if (client != null) client.close();
      } catch (e) {
        print('');
      }
      try {
        if (client2 != null) client2.close();
      } catch (e) {
        print('');
      }
    },
    skip: ngrok_skipped,
  );

  test(
    'Déconnexion client',
    () async {
      var data = <String>[];
      var client = SseClient.fromUriAndPath(uri, path);
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
      var client = SseClient.fromUriAndPath(uri, path);
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
const path = '/sync';
var uri = Uri.parse('http://$host_url');

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

  courses_sse.listen(sse_server);

  final cascade = Cascade().add(courses_sse).add(sse_server.handler);
  final pipeline = const Pipeline().addHandler(cascade.handler);

  return io.serve(pipeline, host, int.parse(port));
}
