import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockOutboundConnectionImpl extends Mock
    implements OutboundConnectionImpl {}

void main() {
  OutboundConnection mockOutBoundConnection = MockOutboundConnectionImpl();

  group('A group of tests to verify buffer of outbound message listener', () {
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(mockOutBoundConnection);
    test('A test to validate complete data comes in single packet', () async {
      outboundMessageListener
          .messageHandler('data:phone@alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:phone@alice');
    });

    test(
        'A test to validate complete data comes in packet and prompt in different packet',
        () async {
      outboundMessageListener
          .messageHandler('data:@bob:phone@alice\n'.codeUnits);
      outboundMessageListener.messageHandler('@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:@bob:phone@alice');
    });

    test('A test to validate data two complete data comes in single packets',
        () async {
      outboundMessageListener
          .messageHandler('data:@bob:phone@alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:@bob:phone@alice');
      outboundMessageListener
          .messageHandler('data:public:phone@alice\n@alice@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:public:phone@alice');
    });

    test('A test to validate data two complete data comes in multiple packets',
        () async {
      outboundMessageListener
          .messageHandler('data:public:phone@alice\n@ali'.codeUnits);
      outboundMessageListener.messageHandler('ce@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:public:phone@alice');
      outboundMessageListener.messageHandler(
          'data:@bob:location@alice,@bob:phone@alice\n@alice@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:@bob:location@alice,@bob:phone@alice');
    });

    test('A test to validate single data comes two packets', () async {
      outboundMessageListener.messageHandler('data:public:phone@'.codeUnits);
      outboundMessageListener.messageHandler('alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:public:phone@alice');
    });

    test('A test to validate data contains @', () async {
      outboundMessageListener
          .messageHandler('data:phone@alice_12345675\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:phone@alice_12345675');
    });

    test(
        'A test to validate data contains @ and partial prompt of previous data',
        () async {
      // partial response of previous data.
      outboundMessageListener.messageHandler('data:hello\n@'.codeUnits);
      outboundMessageListener.messageHandler('alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:hello');
      outboundMessageListener
          .messageHandler('data:phone@alice_12345675\n@alice@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:phone@alice_12345675');
    });

    test('A test to validate data contains new line character', () async {
      outboundMessageListener.messageHandler(
          'data:value_contains_\nin_the_value\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:value_contains_\nin_the_value');
    });
  });

  group('A group of test to verify response from unauth connection', () {
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(mockOutBoundConnection);
    test('A test to validate response from unauth connection', () async {
      outboundMessageListener.messageHandler('data:hello\n@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:hello');
    });

    test('A test to validate multiple response from unauth connection',
        () async {
      outboundMessageListener.messageHandler('data:hello\n@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:hello');
      outboundMessageListener.messageHandler('data:hi\n@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:hi');
    });

    test(
        'A test to validate response from unauth connection in multiple packets',
        () async {
      outboundMessageListener
          .messageHandler('data:public:location@alice,'.codeUnits);
      outboundMessageListener.messageHandler('public:phone@alice\n@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'data:public:location@alice,public:phone@alice');
      outboundMessageListener.messageHandler('data:hi\n@'.codeUnits);
      response = await outboundMessageListener.read();
      expect(response, 'data:hi');
    });
  });

  group('A group of test to validate buffer over flow scenarios', () {
    test('A test to verify buffer over flow exception', () {
      OutboundMessageListener outboundMessageListener =
          OutboundMessageListener(mockOutBoundConnection, bufferCapacity: 10);
      expect(
          () => outboundMessageListener
              .messageHandler('data:dummy_data_to_exceed_limit'.codeUnits),
          throwsA(predicate((dynamic e) =>
              e is BufferOverFlowException &&
              e.message ==
                  'data length exceeded the buffer limit. Data length : 31 and Buffer capacity 10')));
    });

    test('A test to verify buffer over flow with multiple data packets', () {
      OutboundMessageListener outboundMessageListener =
          OutboundMessageListener(mockOutBoundConnection, bufferCapacity: 20);
      outboundMessageListener.messageHandler('data:dummy_data'.codeUnits);
      expect(
          () => outboundMessageListener
              .messageHandler('to_exceed_limit\n@alice@'.codeUnits),
          throwsA(predicate((dynamic e) =>
              e is BufferOverFlowException &&
              e.message ==
                  'data length exceeded the buffer limit. Data length : 38 and Buffer capacity 20')));
    });
  });

  group('A group of tests to verify error: and stream responses from server',
      () {
    OutboundMessageListener outboundMessageListener =
        OutboundMessageListener(mockOutBoundConnection);
    test('A test to validate complete error comes in single packet', () async {
      outboundMessageListener.messageHandler(
          'error:AT0012: Invalid value found\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'error:AT0012: Invalid value found');
    });

    test('A test to validate complete error comes in single packet', () async {
      outboundMessageListener
          .messageHandler('stream:@bob:phone@alice\n@alice@'.codeUnits);
      var response = await outboundMessageListener.read();
      expect(response, 'stream:@bob:phone@alice');
    });
  });
}
