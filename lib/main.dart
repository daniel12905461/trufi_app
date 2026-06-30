import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(MyApp());
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  static const String incrementCountCommand = 'incrementCount';

  WebSocketChannel? _channel;

  int _count = 0;

  Future<void> _connectWebSocket() async {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://192.168.1.5:8000/ws'),
      );

      _channel!.stream.listen(
        (message) async {
          print('[BACKGROUND] WebSocket message: $message');

          // Mandar el mensaje al hilo principal (si la app está abierta)
          FlutterForegroundTask.sendDataToMain(message);
        },
        onError: (e) {
          print('WebSocket error: $e');
        },
        onDone: () {
          print('WebSocket closed, reconnecting in 5s...');
          Future.delayed(Duration(seconds: 5), _connectWebSocket);
        },
      );
    } catch (e) {
      print('WebSocket connect error: $e');
      Future.delayed(Duration(seconds: 5), _connectWebSocket);
    }
  }

  void _incrementCount() {
    _count++;

    // Update notification content.
    FlutterForegroundTask.updateService(
      notificationTitle: 'Servicio WebSocket activo',
      notificationText: 'Mensajes recibidos: $_count',
    );

    // Send data to main isolate.
    FlutterForegroundTask.sendDataToMain(_count);
  }

  // Called when the task is started.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('onStart(starter: ${starter.name})');
    // _incrementCount();
    await _connectWebSocket();
  }

  // Called based on the eventAction set in ForegroundTaskOptions.
  @override
  void onRepeatEvent(DateTime timestamp) {
    // _incrementCount();
    // _channel?.sink.add('hola mundo daniel dc');
    _sendCurrentLocation();
  }

  // Called when the task is destroyed.
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('onDestroy(isTimeout: $isTimeout)');
    await _channel?.sink.close();
  }

  // Called when data is sent using `FlutterForegroundTask.sendDataToTask`.
  @override
  void onReceiveData(Object data) {
    print('onReceiveData: $data');
    // if (data == incrementCountCommand) {
    // _incrementCount();
    // } else if (data is String) {
    _channel?.sink.add(
      'ehh recibido esto: $data',
    ); // ✅ Enviar mensaje al WebSocket desde UI
    // }
  }

  // Called when the notification button is pressed.
  @override
  void onNotificationButtonPressed(String id) {
    print('onNotificationButtonPressed: $id');
  }

  // Called when the notification itself is pressed.
  @override
  void onNotificationPressed() {
    print('onNotificationPressed');
  }

  // Called when the notification itself is dismissed.
  @override
  void onNotificationDismissed() {
    print('onNotificationDismissed');
  }

  Future<void> _sendCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final data = {
        "type": "location",
        "lat": position.latitude,
        "lng": position.longitude,
        "speed": position.speed,
        "accuracy": position.accuracy,
        "timestamp": DateTime.now().toIso8601String(),
      };

      _channel?.sink.add(jsonEncode(data));

      print("Ubicación enviada: $data");
    } catch (e) {
      print("Error obteniendo ubicación: $e");
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'WebSocket con FastAPI',
      home: WebSocketExample(),
    );
  }
}

class WebSocketExample extends StatefulWidget {
  const WebSocketExample({super.key});

  @override
  State<WebSocketExample> createState() => _WebSocketExampleState();
}

class _WebSocketExampleState extends State<WebSocketExample> {
  final ValueNotifier<Object?> _taskDataListenable = ValueNotifier(null);

  late WebSocketChannel channel;
  // final TextEditingController _controller = TextEditingController();
  final List<String> _messages = [];

  Future<void> _requestPermissions() async {
    // Android 13+, you need to allow notification permission to display foreground service notification.
    //
    // iOS: If you need notification, ask for permission.
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (Platform.isAndroid) {
      // Android 12+, there are restrictions on starting a foreground service.
      //
      // To restart the service on device reboot or unexpected problem, you need to allow below permission.
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        // This function requires `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission.
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // Use this utility only if you provide services that require long-term survival,
      // such as exact alarm service, healthcare service, or Bluetooth communication.
      //
      // This utility requires the "android.permission.SCHEDULE_EXACT_ALARM" permission.
      // Using this permission may make app distribution difficult due to Google policy.
      if (!await FlutterForegroundTask.canScheduleExactAlarms) {
        // When you call this function, will be gone to the settings page.
        // So you need to explain to the user why set it.
        await FlutterForegroundTask.openAlarmsAndRemindersSettings();
      }
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception("Permiso de ubicación denegado");
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      throw Exception("Permiso denegado permanentemente");
    }
  }

  void _initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<ServiceRequestResult> _startService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.restartService();
    } else {
      return FlutterForegroundTask.startService(
        // You can manually specify the foregroundServiceType for the service
        // to be started, as shown in the comment below.
        // serviceTypes: [
        //   ForegroundServiceTypes.dataSync,
        //   ForegroundServiceTypes.remoteMessaging,
        // ],
        serviceId: 256,
        notificationTitle: 'Foreground Service is running',
        notificationText: 'Tap to return to the app',
        notificationIcon: null,
        notificationButtons: [
          const NotificationButton(id: 'btn_hello', text: 'hello'),
        ],
        notificationInitialRoute: '/second',
        callback: startCallback,
      );
    }
  }

  Future<ServiceRequestResult> _stopService() {
    return FlutterForegroundTask.stopService();
  }

  void _onReceiveTaskData(Object data) {
    print('onReceiveTaskData: $data');
    _taskDataListenable.value = data;
  }

  void _incrementCount() {
    FlutterForegroundTask.sendDataToTask(MyTaskHandler.incrementCountCommand);
  }

  @override
  void initState() {
    super.initState();

    // channel = WebSocketChannel.connect(Uri.parse('ws://192.168.1.7:8000/ws'));

    // channel.stream.listen((message) {
    //   setState(() {
    //     _messages.add(message);
    //   });
    // });

    // Add a callback to receive data sent from the TaskHandler.
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Request permissions and initialize the service.
      await _requestPermissions();
      _initService();
    });
  }

  void _sendMessage() {
    // if (_controller.text.isNotEmpty) {
    //   channel.sink.add(_controller.text);
    //   _controller.clear();
    // }
  }

  void _sendMessageToBackground() {
    FlutterForegroundTask.sendDataToTask('Hola desde la UI!');
  }

  @override
  void dispose() {
    channel.sink.close(status.goingAway);

    // Remove a callback to receive data sent from the TaskHandler.
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _taskDataListenable.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebSocket con FastAPI 🚀')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) =>
                  ListTile(title: Text(_messages[index])),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Expanded(
                //   child: TextField(
                //     controller: _controller,
                //     decoration: const InputDecoration(
                //       labelText: 'Escribe un mensaje',
                //     ),
                //   ),
                // ),
                IconButton(
                  icon: const Icon(Icons.start),
                  onPressed: () async {
                    await _requestPermissions();
                    await _startService();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: _stopService,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _incrementCount,
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessageToBackground,
                ),
                // _buildServiceControlButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceControlButtons() {
    buttonBuilder(String text, {VoidCallback? onPressed}) {
      return ElevatedButton(onPressed: onPressed, child: Text(text));
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buttonBuilder('start service', onPressed: _startService),
          buttonBuilder('stop service', onPressed: _stopService),
          buttonBuilder('increment count', onPressed: _incrementCount),
        ],
      ),
    );
  }
}
