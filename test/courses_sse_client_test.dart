import 'dart:async';
import 'dart:io';

import 'package:courses_sse_client/courses_sse_client.dart' show SseClient;
import 'package:http/http.dart';
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
        client2 = SseClient.fromUriAndPath(uri_ngrok, path);
        await client2.onConnected;
      } catch (e) {
        assert(false, 'Erreur de connexion');
      }

      runZonedGuarded(
        () {
          client!.stream.listen((event) => data.add(event));
          client2!.stream.listen((event) => data.add(event));
        },
        (e, s) {
          // Lorsqu'on _close_ un client, il est possible de recevoir une erreur
          // asynchrone 'Connection closed while receiving data' sur le listen
          // Cette erreur ne peut pas être attrapée dans un `try / catch` et
          // remonte donc jusqu'à la zone d'erreur _root_. En exécutant le
          // `listen` dans sa propre zone d'erreur, on peut _catcher_ cette
          // `ClientException`. Dans notre cas, ce n'est pas une erreur, le
          // `close` fait partie du test.
          assert(e is ClientException);
          print('OK: $e');
        },
      );

      client!.close();
      client2!.close();
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
