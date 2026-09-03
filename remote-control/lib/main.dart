import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/gesture_description.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerdart/peerdart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RemoteControlApp());
}

class RemoteControlApp extends StatelessWidget {
  const RemoteControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remote Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3157d5)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

enum AppMode { host, viewer }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final TextEditingController _hostIdController = TextEditingController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Peer? _peer;
  MediaConnection? _currentCall;
  DataConnection? _dataConnection;
  MediaStream? _screenStream;
  MediaStream? _viewerStream;

  AppMode _mode = AppMode.viewer;
  String? _peerId;
  String? _errorMessage;
  bool _isBusy = false;
  bool _isConnected = false;
  bool _accessibilityEnabled = false;
  bool _renderersInitialized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await Future.wait([
      _localRenderer.initialize(),
      _remoteRenderer.initialize(),
    ]);
    _renderersInitialized = true;
    if (!mounted) {
      unawaited(_localRenderer.dispose());
      unawaited(_remoteRenderer.dispose());
      return;
    }
    await _refreshAccessibilityStatus();
    if (!mounted) return;
    await _initializePeer();
  }

  Future<void> _refreshAccessibilityStatus() async {
    final enabled =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (mounted) {
      setState(() => _accessibilityEnabled = enabled);
    }
  }

  Future<void> _initializePeer() async {
    final peer = Peer(
      options: PeerOptions(
        host: '0.peerjs.com',
        port: 443,
        path: '/',
        secure: true,
      ),
    );
    _peer = peer;

    _subscriptions.add(peer.on<String>('open').listen((id) {
      if (!mounted) return;
      setState(() {
        _peerId = id;
        _errorMessage = null;
      });
    }));

    _subscriptions.add(peer.on<MediaConnection>('call').listen((call) {
      unawaited(_handleIncomingCall(call));
    }));

    _subscriptions.add(
      peer.on<DataConnection>('connection').listen(_handleDataConnection),
    );

    _subscriptions.add(peer.on<dynamic>('error').listen((error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Peer connection error: $error');
    }));
  }

  Future<void> _handleIncomingCall(MediaConnection call) async {
    if (_mode != AppMode.host || _screenStream == null) {
      call.close();
      return;
    }

    call.answer(_screenStream!);
    _currentCall = call;
    _subscriptions.add(call.on<dynamic>('close').listen((_) {
      if (!mounted) return;
      setState(() => _isConnected = false);
    }));
    if (mounted) {
      setState(() => _isConnected = true);
    }
  }

  void _handleDataConnection(DataConnection connection) {
    _dataConnection = connection;
    _subscriptions.add(connection.on<dynamic>('open').listen((_) {
      if (!mounted) return;
      setState(() => _isConnected = true);
    }));
    _subscriptions.add(connection.on<dynamic>('close').listen((_) {
      if (!mounted) return;
      setState(() => _isConnected = false);
    }));
    _subscriptions.add(connection.on<dynamic>('data').listen((data) {
      if (data is Map) {
        unawaited(_handleRemoteInput(data));
      }
    }));
  }

  Future<MediaStream?> _startScreenCapture() async {
    final granted = await Helper.requestCapturePermission();
    if (!granted) {
      _setError('Screen capture permission was not granted.');
      return null;
    }

    try {
      return await navigator.mediaDevices.getDisplayMedia({
        'video': {'cursor': 'always'},
        'audio': false,
      });
    } catch (error) {
      _setError('Could not start screen capture: $error');
      return null;
    }
  }

  Future<void> _startHosting() async {
    if (_peerId == null || _isBusy) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    final stream = await _startScreenCapture();
    if (!mounted) return;
    if (stream == null) {
      setState(() => _isBusy = false);
      return;
    }

    _screenStream = stream;
    _localRenderer.srcObject = stream;
    setState(() {
      _mode = AppMode.host;
      _isBusy = false;
    });
  }

  Future<void> _connectAsViewer() async {
    final hostId = _hostIdController.text.trim();
    final peer = _peer;
    if (peer == null || hostId.isEmpty || _isBusy) return;

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      _viewerStream ??= await createLocalMediaStream('remote-control-viewer');
      final call = peer.call(hostId, _viewerStream!);
      _currentCall = call;
      _subscriptions.add(call.on<MediaStream>('stream').listen((stream) {
        _remoteRenderer.srcObject = stream;
        if (!mounted) return;
        setState(() {
          _isConnected = true;
          _isBusy = false;
        });
      }));
      _subscriptions.add(call.on<dynamic>('close').listen((_) {
        if (!mounted) return;
        setState(() => _isConnected = false);
      }));
      _handleDataConnection(peer.connect(hostId));
    } catch (error) {
      _setError('Could not connect to host: $error');
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handleRemoteInput(Map data) async {
    if (data['type'] != 'touch') return;
    final x = (data['x'] as num?)?.toDouble();
    final y = (data['y'] as num?)?.toDouble();
    if (x == null || y == null || !_accessibilityEnabled) return;

    final view = PlatformDispatcher.instance.views.first;
    final width = view.physicalSize.width;
    final height = view.physicalSize.height;
    final point = GesturePoint(
      (x.clamp(0, 1) * width).toDouble(),
      (y.clamp(0, 1) * height).toDouble(),
    );

    await FlutterAccessibilityService.dispatchGesture(
      GestureDescription(
        strokes: [
          GestureStroke(path: [point], startTime: 0, duration: 100),
        ],
      ),
    );
  }

  void _sendTouch(Offset localPosition, Size size) {
    final connection = _dataConnection;
    if (connection == null || size.width <= 0 || size.height <= 0) return;

    connection.send({
      'type': 'touch',
      'x': (localPosition.dx / size.width).clamp(0.0, 1.0),
      'y': (localPosition.dy / size.height).clamp(0.0, 1.0),
    });
  }

  Future<void> _enableAccessibility() async {
    await FlutterAccessibilityService.requestAccessibilityPermission();
    await _refreshAccessibilityStatus();
  }

  void _setError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _stopSession({bool notify = true}) {
    _currentCall?.close();
    _dataConnection?.close();
    _screenStream?.getTracks().forEach((track) => track.stop());
    _screenStream = null;
    if (_renderersInitialized) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
    }
    if (notify && mounted) {
      setState(() {
        _isConnected = false;
        _isBusy = false;
      });
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _stopSession(notify: false);
    _peer?.disconnect();
    _viewerStream?.dispose();
    if (_renderersInitialized) {
      _localRenderer.dispose();
      _remoteRenderer.dispose();
    }
    _hostIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHost = _mode == AppMode.host;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Control'),
        actions: [
          if (_isConnected)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.circle, color: Colors.green, size: 12),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildIdentityCard(),
            const SizedBox(height: 16),
            SegmentedButton<AppMode>(
              segments: const [
                ButtonSegment(value: AppMode.viewer, label: Text('Viewer')),
                ButtonSegment(value: AppMode.host, label: Text('Host')),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty && selection.first != _mode) {
                  _stopSession();
                  setState(() => _mode = selection.first);
                }
              },
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null) _buildErrorBanner(),
            if (isHost) _buildHostPanel() else _buildViewerPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your connection ID', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SelectableText(
              _peerId ?? 'Connecting to PeerJS…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Share this ID only with the person you want to connect.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MaterialBanner(
        content: Text(_errorMessage!),
        leading: const Icon(Icons.warning_amber_rounded),
        actions: [
          TextButton(
            onPressed: () => setState(() => _errorMessage = null),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Widget _buildHostPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Host mode', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('Share this device screen with one connected viewer.'),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _screenStream == null
                ? const _EmptyVideoState(
                    icon: Icons.screen_share_outlined,
                    message: 'Screen sharing is not active',
                  )
                : RTCVideoView(_localRenderer, mirror: false),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _peerId == null || _isBusy ? null : _startHosting,
          icon: const Icon(Icons.screen_share),
          label: Text(_isBusy ? 'Starting…' : 'Start screen sharing'),
        ),
        if (_screenStream != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _stopSession,
            child: const Text('Stop sharing'),
          ),
        ],
        const SizedBox(height: 16),
        _buildAccessibilityCard(),
      ],
    );
  }

  Widget _buildViewerPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Viewer mode', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('Connect to a host, then tap or drag on the shared screen.'),
        const SizedBox(height: 16),
        TextField(
          controller: _hostIdController,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Host connection ID',
            hintText: 'Paste the host ID',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _connectAsViewer(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _peerId == null || _isBusy ? null : _connectAsViewer,
          icon: const Icon(Icons.link),
          label: Text(_isBusy ? 'Connecting…' : 'Connect to host'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 420,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _remoteRenderer.srcObject == null
                ? const _EmptyVideoState(
                    icon: Icons.connected_tv_outlined,
                    message: 'The host screen will appear here',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _sendTouch(details.localPosition, constraints.biggest),
                        onPanUpdate: (details) =>
                            _sendTouch(details.localPosition, constraints.biggest),
                        child: RTCVideoView(_remoteRenderer),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccessibilityCard() {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _accessibilityEnabled
                  ? Icons.check_circle_outline
                  : Icons.accessibility_new,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _accessibilityEnabled
                        ? 'Accessibility control enabled'
                        : 'Enable accessibility control',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _accessibilityEnabled
                        ? 'The host can receive touch gestures.'
                        : 'Android requires this permission before remote touches can be delivered.',
                  ),
                  if (!_accessibilityEnabled) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _enableAccessibility,
                      child: const Text('Open accessibility settings'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyVideoState extends StatelessWidget {
  const _EmptyVideoState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42),
            const SizedBox(height: 12),
            Text(message),
          ],
        ),
      ),
    );
  }
}