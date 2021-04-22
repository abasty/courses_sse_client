import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:stream_channel/stream_channel.dart';

import '../courses_sse_client.dart';

SseClient getSseClient(String serverUrl) => SseClientIo(serverUrl);

class SseClientIo extends StreamChannelMixin<String> implements SseClient {
  @override
  Future<void> get onConnected => _onConnected.future;

  /// Add messages to this [StreamSink] to send them to the server.
  ///
  /// The message added to the sink has to be JSON encodable. Messages that fail
  /// to encode will be logged through a [Logger].
  @override
  StreamSink<String> get sink => _outgoingController.sink;

  /// [Stream] of messages sent from the server to this client.
  ///
  /// A message is a decoded JSON object.
  @override
  Stream<String> get stream => _incomingController.stream;

  late final StreamController<String> _incomingController;
  final _outgoingController = StreamController<String>();
  // final _logger = Logger('SseClient');
  final _onConnected = Completer();
  // int _lastMessageId = -1;
  late String _serverUrl;
  final _client = http.Client();
  final _clientId = randomSseClientId();

  SseClientIo(String serverUrl) {
    _serverUrl = '$serverUrl?sseClientId=$_clientId';

    _incomingController = StreamController<String>.broadcast(
      onListen: () {
        var request = http.Request('GET', Uri.parse(_serverUrl))
          ..headers['Cache-Control'] = 'no-cache'
          ..headers['Accept'] = 'text/event-stream';

        _client.send(request).then(
          (response) {
            if (response.statusCode == 200) {
              _onConnected.complete();
              response.stream
                  .transform(utf8.decoder)
                  .transform(LineSplitter())
                  .listen((str) {
                if (str.startsWith('data: ')) {
                  str = str.substring(7, str.length - 1).replaceAll('\\"', '"');
                  _incomingController.sink.add(str);
                }
              });
            } else {
              _incomingController
                  .addError(Exception('Failed to connect to $_serverUrl'));
              close();
              if (!_onConnected.isCompleted) {
                _onConnected.completeError(response.statusCode);
              }
            }
          },
        );
      },
      onCancel: () {
        _incomingController.close();
      },
    );
  }

  @override
  void close() {
    // If the initial connection was never established. Add a listener so close
    // adds a done event to [sink].
    if (!_onConnected.isCompleted) _outgoingController.stream.drain();
    _incomingController.close();
    _outgoingController.close();
  }

  @override
  String get clientId => _clientId;
}
