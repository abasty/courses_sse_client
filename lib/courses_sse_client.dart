import 'dart:math';

import 'package:stream_channel/stream_channel.dart';

import 'src/courses_sse_client_stub.dart'
    if (dart.library.io) 'src/courses_sse_client_io.dart'
    if (dart.library.html) 'src/courses_sse_client_html.dart';

String randomSseClientId() {
  var r = Random().nextInt(1 << 31) + 1;
  return r.toString();
}

abstract class SseClient extends StreamChannelMixin<String> {
  Future<void> get onConnected;
  String get clientId;

  /// Returns a new [SseClient]
  factory SseClient.fromUrl(String serverUrl) {
    return getSseClient(serverUrl);
  }

  /// Closes the [SseClient]
  void close();
}
