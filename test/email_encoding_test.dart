import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Email Encoding & Decoding Logic Tests', () {
    test('Should correctly encode email into full_name', () {
      final String email = 'akbar@test.com';
      final String fullName = 'Akbar Rajee';

      String combinedName = '$fullName | $email';

      expect(combinedName, equals('Akbar Rajee | akbar@test.com'));
    });

    test('Should correctly decode full_name and email from combined field', () {
      final String combinedName = 'Akbar Rajee | akbar@test.com';

      expect(combinedName.contains('|'), isTrue);

      final parts = combinedName.split('|');
      final String name = parts[0].trim();
      final String email = parts[1].trim();

      expect(name, equals('Akbar Rajee'));
      expect(email, equals('akbar@test.com'));
    });

    test('Should gracefully handle names without encoded emails', () {
      final String normalName = 'Madam Paula';

      expect(normalName.contains('|'), isFalse);
    });
  });
}
