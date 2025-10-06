import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class WebSocketService {
  late WebSocketChannel _channel;

  void connect(String url) {
    _channel = WebSocketChannel.connect(Uri.parse(url));
  }

  void sendMessage(String message) {
    _channel.sink.add(message);
  }

  Stream get messages => _channel.stream;

  void disconnect() {
    _channel.sink.close(status.goingAway);
  }
}
