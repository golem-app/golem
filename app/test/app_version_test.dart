import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/app_version.dart';

void main() {
  test('About prints the version alone unless a device build is stamped', () {
    expect(aboutVersionLabel(version: '1.0.0', stamp: ''), '1.0.0');
    // tool/device_install.sh stamps the commit so a tester can tell which
    // build is in hand; a trailing + marks an uncommitted tree.
    expect(
      aboutVersionLabel(version: '1.0.0', stamp: 'f722edc'),
      '1.0.0 · f722edc',
    );
    expect(
      aboutVersionLabel(version: '1.0.0', stamp: 'f722edc+'),
      '1.0.0 · f722edc+',
    );
  });
}
