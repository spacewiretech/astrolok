import 'package:astrolok/data/sms/sms_code_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one piece of SMS autofill that is ours rather than Android's: finding the code in the text.
///
/// A wrong match here does not fail loudly. It fills six plausible digits and auto-submits them,
/// so the user sees "That code is not right" for a message that held the right one.
void main() {
  group('SmartAuthSmsCodeReader.codeFrom', () {
    test('takes the code out of an OTP message', () {
      expect(
        SmartAuthSmsCodeReader.codeFrom('482915 is your Astrolok verification code.', 6),
        '482915',
      );
    });

    test('ignores the Retriever hash at the end of the message', () {
      expect(
        SmartAuthSmsCodeReader.codeFrom('Use 482915 to sign in to Astrolok.\nFA+9qCX9VSu', 6),
        '482915',
      );
    });

    test('never takes part of a longer number, or a shorter one', () {
      // smart_auth's own matcher would take the first four digits of the helpline here.
      expect(SmartAuthSmsCodeReader.codeFrom('Call 9876543210 for help', 6), isNull);
      expect(SmartAuthSmsCodeReader.codeFrom('Your code is 1234', 6), isNull);
      expect(
        SmartAuthSmsCodeReader.codeFrom('Call 9876543210. Your code is 482915', 6),
        '482915',
      );
    });

    test('no message, no code', () {
      expect(SmartAuthSmsCodeReader.codeFrom(null, 6), isNull);
    });
  });

  test('the stand-in never listens and never finds anything', () async {
    const reader = NoopSmsCodeReader();

    expect(reader.available, isFalse);
    expect(await reader.waitForCode(retriever: false), isNull);
    expect(await reader.waitForCode(retriever: true), isNull);
  });
}
