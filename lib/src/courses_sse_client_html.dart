// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:logging/logging.dart';
import 'package:stream_channel/stream_channel.dart';

import '../courses_sse_client.dart';

SseClient getSseClient(Uri uri, String path) => SseClientHtml(uri, path);

/// A client for bi-directional sse communcation.
///
/// The client can send any JSON-encodable messages to the server by adding
/// them to the [sink] and listen to messages from the server on the [stream].
class SseClientHtml extends StreamChannelMixin<String> implements SseClient {
  final _incomingController = StreamController<String>();

  final _outgoingController = StreamController<String>();

  final _logger = Logger('SseClient');

  final _onConnected = Completer();

  int _lastMessageId = -1;

  late final EventSource _eventSource;

  late final String _serverUrl;
  final Uri _uri;
  final String _path;

  Timer? _errorTimer;

  final _clientId = randomSseClientId();

  /// [serverUrl] is the URL under which the server is listening for
  /// incoming bi-directional SSE connections.
  SseClientHtml(this._uri, this._path) {
    _serverUrl = _uri.toString() + _path + '?sseClientId=$_clientId';
    _eventSource = EventSource(_serverUrl, withCredentials: false);
    _eventSource.onOpen.first.whenComplete(() {
      _onConnected.complete();
      _outgoingController.stream
          .listen(_onOutgoingMessage, onDone: _onOutgoingDone);
    });
    _eventSource.addEventListener('message', _onIncomingMessage);
    _eventSource.addEventListener('control', _onIncomingControlMessage);

    _eventSource.onOpen.listen((_) {
      _errorTimer?.cancel();
    });
    _eventSource.onError.listen((error) {
      if (!(_errorTimer?.isActive ?? false)) {
        // By default the SSE client uses keep-alive.
        // Allow for a retry to connect before giving up.
        // abasty a changé le timer à 0 pour l'article
        _errorTimer = Timer(const Duration(seconds: 0), () {
          close();
          if (!_onConnected.isCompleted) {
            // This call must happen after the call to close() which checks
            // whether the completer was completed earlier.
            _onConnected.completeError(error);
          }
        });
      }
    });
  }

  @Deprecated('Use onConnected instead.')
  Stream<Event> get onOpen => _eventSource.onOpen;

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

  @override
  void close() {
    _eventSource.close();
    // If the initial connection was never established. Add a listener so close
    // adds a done event to [sink].
    if (!_onConnected.isCompleted) _outgoingController.stream.drain();
    _incomingController.close();
    _outgoingController.close();
  }

  void _onIncomingControlMessage(Event message) {
    var data = (message as MessageEvent).data;
    if (data == 'close') {
      close();
    } else {
      throw UnsupportedError('Illegal Control Message "$data"');
    }
  }

  void _onIncomingMessage(Event message) {
    var decoded =
        jsonDecode((message as MessageEvent).data as String) as String;
    _incomingController.add(decoded);
  }

  void _onOutgoingDone() {
    close();
  }

  void _onOutgoingMessage(String message) async {
    String? encodedMessage;
    try {
      encodedMessage = jsonEncode(message);
    } on JsonUnsupportedObjectError catch (e) {
      _logger.warning('Unable to encode outgoing message: $e');
    } on ArgumentError catch (e) {
      _logger.warning('Invalid argument: $e');
    }
    try {
      await HttpRequest.request('$_serverUrl&messageId=${++_lastMessageId}',
          method: 'POST', sendData: encodedMessage, withCredentials: true);
    } catch (e) {
      _logger.severe('Failed to send $message:\n $e');
      close();
    }
  }

  @override
  String get clientId => _clientId;
}
