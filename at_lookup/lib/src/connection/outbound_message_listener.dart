import 'dart:collection';
import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

///Listener class for messages received by [RemoteSecondary]
class OutboundMessageListener {
  final logger = AtSignLogger('OutboundMessageListener');
  late ByteBuffer _buffer;
  final Queue _queue = Queue();
  final _connection;
  Function? syncCallback;
  final int terminatingChar = 10;
  final int atCharCodeUnit = 64;

  OutboundMessageListener(this._connection, {int bufferCapacity = 10240000}) {
    _buffer = ByteBuffer(capacity: bufferCapacity);
  }

  /// Listens to the underlying connection's socket if the connection is created.
  /// @throws [AtConnectException] if the connection is not yet created
  void listen() {
    _connection.getSocket().listen(messageHandler,
        onDone: _finishedHandler, onError: _errorHandler);
  }

  /// Handles messages on the inbound client's connection and calls the verb executor
  /// Closes the inbound connection in case of any error.
  /// Throw a [BufferOverFlowException] if buffer is unable to hold incoming data
  Future<void> messageHandler(List data) async {
    String result;
    // check buffer overflow
    _checkBufferOverFlow(data);
    //1. Iterate the list until a new line character is encounter.
    //2. If new line char is encountered, then decode the buffered data (utf8.decode)
    //3. Strip the prompt from the result.
    //4. Add the result to queue.
    for (var element in data) {
      // If element is @ character and lastCharacter in the buffer is \n,
      // then complete data is received. process it.
      if (element == atCharCodeUnit &&
          _buffer.getData().last == terminatingChar) {
        result = utf8.decode(_buffer.getData());
        result = _stripPrompt(result);
        _queue.add(result);
        //clear the buffer after adding result to queue
        _buffer.clear();
      } else {
        _buffer.addByte(element);
      }
    }
  }

  /// The methods verifies if buffer has the capacity to accept the data.
  ///
  /// Throw BufferOverFlowException if data length exceeds the buffer capacity
  _checkBufferOverFlow(data) {
    if (_buffer.isOverFlow(data)) {
      int bufferLength = (_buffer.length() + data.length) as int;
      _buffer.clear();
      throw BufferOverFlowException(
          'data length exceeded the buffer limit. Data length : $bufferLength and Buffer capacity ${_buffer.capacity}');
    }
  }

  /// The method accepts the result (server response) and trim's the prompt from the response
  /// and returns the actual response.
  String _stripPrompt(String result) {
    // trim the \n character in the last.
    result = result.trim();
    var colonIndex = result.indexOf(':');
    var responsePrefix = result.substring(0, colonIndex);
    var response = result.substring(colonIndex);
    if (responsePrefix.contains('@')) {
      responsePrefix =
          responsePrefix.substring(responsePrefix.lastIndexOf('@') + 1);
    }
    return '$responsePrefix$response';
  }

  /// Reads the response sent by remote socket from the queue.
  /// If there is no message in queue after [maxWaitMilliSeconds], return null. Defaults to 3 seconds.
  Future<String> read({int maxWaitMilliSeconds = 10000}) async {
    return _read(maxWaitMillis: maxWaitMilliSeconds);
  }

  Future<String> _read({int maxWaitMillis = 10000, int retryCount = 1}) async {
    String result;
    var maxIterations = maxWaitMillis / 10;
    if (retryCount == maxIterations) {
      _buffer.clear();
      throw AtTimeoutException(
          'No response after $maxWaitMillis millis from remote secondary');
    }
    var queueLength = _queue.length;
    if (queueLength > 0) {
      result = _queue.removeFirst();
      // result from another secondary is either data or a @<atSign>@ denoting complete
      // of the handshake
      if (_isValidResponse(result)) {
        return result;
      }
      //ignore any other response
      _buffer.clear();
      throw AtLookUpException('AT0014', 'Unexpected response found');
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
    logger.finest('outbound finish handler called');
    await _closeConnection();
  }

  Future<void> _closeConnection() async {
    if (!_connection.isInValid()) {
      await _connection.close();
    }
  }
}
