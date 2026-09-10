import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iranlink/src/core/port_probe.dart';

void main() {
  test('parseNetstatOwner finds LISTENING pid', () {
    const output = '''
  TCP    127.0.0.1:10808          0.0.0.0:0              LISTENING       4242
  TCP    [::1]:10809              [::]:0                 LISTENING       9999
''';
    expect(parseNetstatOwner(output, 10808), 4242);
    expect(parseNetstatOwner(output, 10809), 9999);
    expect(parseNetstatOwner(output, 1), isNull);
  });

  test('isPortFree detects bound port', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    try {
      expect(await isPortFree('127.0.0.1', port), isFalse);
    } finally {
      await server.close();
    }
    expect(await isPortFree('127.0.0.1', port), isTrue);
  });
}
