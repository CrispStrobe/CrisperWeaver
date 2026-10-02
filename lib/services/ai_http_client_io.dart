import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../constants/build_flavor.dart';

http.Client createAiHttpClient() {
  final client = HttpClient();
  if (BuildFlavor.isLite) {
    // A system HTTP proxy must not receive local prompts or credentials.
    client.findProxy = (_) => 'DIRECT';
  }
  return IOClient(client);
}
