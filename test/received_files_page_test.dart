import 'package:flutter_test/flutter_test.dart';
import 'package:sharem/src/ui/received_files_page.dart';

void main() {
  test('hides partial file names from received file manager', () {
    expect(isUserReceivedFile('.sharem-abcd.part'), isFalse);
    expect(isUserReceivedFile('unfinished.part'), isFalse);
    expect(isUserReceivedFile('family.png'), isTrue);
    expect(isUserReceivedFile(''), isFalse);
  });
}
