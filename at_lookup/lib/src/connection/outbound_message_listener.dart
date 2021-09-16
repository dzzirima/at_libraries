import 'dart:collection';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

///Listener class for messages received by [RemoteSecondary]
class OutboundMessageListener {
  final logger = AtSignLogger('OutboundMessageListener');
  final _buffer = ByteBuffer(capacity: 10240000);
  late Queue _queue;
  final _connection;
  Function? syncCallback;

  OutboundMessageListener(this._connection);

  /// Listens to the underlying connection's socket if the connection is created.
  /// @throws [AtConnectException] if the connection is not yet created
  void listen() {
    _connection.getSocket().listen(messageHandler,
        onDone: _finishedHandler, onError: _errorHandler, cancelOnError: true);
    _queue = Queue();
  }

  /// Handles messages on the inbound client's connection and calls the verb executor
  /// Closes the inbound connection in case of any error.
  /// Throw a [BufferOverFlowException] if buffer is unable to hold incoming data
  Future<void> messageHandler(data) async {
    String result;
    if (!_buffer.isOverFlow(data)) {
      // skip @ prompt
      if (data.length == 1 && data.first == 64) {
        return;
      }
      //ignore prompt(@ or @<atSign>@) after '\n'
      // If data contains 10(utf8 character for '\n'), trim the string after the '\n'
      if (data.contains(10)) {
        data = data.sublist(0, data.lastIndexOf(10) + 1);
      }
      _buffer.append(data);
    } else {
      _buffer.clear();
      throw BufferOverFlowException(
          'Buffer overflow on outbound connection result');
    }
    if (_buffer.isEnd()) {
      result = utf8.decode(_buffer.getData());
      result = result.trim();
      _buffer.clear();
      _queue.addFirst(result);
    }
  }

  /// Reads the response sent by remote socket from the queue.
  /// If there is no message in queue after [maxWaitMilliSeconds], return null. Defaults to 30 seconds.
  Future<String?> read({int maxWaitMilliSeconds = 30000}) async {
    return _read(maxWaitMillis: maxWaitMilliSeconds);
  }

  Future<String?> _read({int maxWaitMillis = 30000, int retryCount = 1}) async {
    var result;
    var maxIterations = maxWaitMillis / 10;
    if (retryCount == maxIterations) {
      _buffer.clear();
      return null;
    }
    var queueLength = _queue.length;
    if (queueLength > 0) {
      result = _queue.removeFirst();
      // result from another secondary is either data or a @<atSign>@ denoting complete
      // of the handshake
      if (_isValidResponse(result)) {
        return result;
      } else {
        //ignore any other response
        _buffer.clear();
        return '';
      }
    }
    return Future.delayed(Duration(milliseconds: 10))
        .then((value) => _read(retryCount: ++retryCount));
  }

  bool _isValidResponse(String result) {
    return result.startsWith('data:') ||
        result.startsWith('stream:') ||
        result.startsWith('error:') ||
        (result.startsWith('@') && result.endsWith('@'));
  }

  /// Logs the error and closes the [RemoteSecondary]
  Future<void> _errorHandler(error) async {
    await _closeConnection();
  }

  /// Closes the [OutboundConnection]
  void _finishedHandler() async {
    print('outbound finish handler called');
    await _closeConnection();
  }

  Future<void> _closeConnection() async {
    if (!_connection.isInValid()) {
      await _connection.close();
    }
  }
}
