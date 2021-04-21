import 'dart:math';

import 'src/courses_sse_client_stub.dart'
    if (dart.library.io) 'src/courses_sse_client_io.dart'
    if (dart.library.html) 'src/courses_sse_client_html.dart';
import 'package:stream_channel/stream_channel.dart';

String randomSseClientId() {
  var r = Random().nextInt(1 << 31) + 1;
  return r.toString();
}

abstract class SseClient extends StreamChannelMixin<String> {
  Future<void> get onConnected;
  String get clientId;
  static SseClient? _instance;

  static SseClient getInstance(String serverUrl) {
    _instance ??= getSseClient(serverUrl);
    return _instance!;
  }
}
