import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:my_app1/services/agora_service.dart';

// ════════════════════════════════════════════════════════════════
//  AGORA CALL SCREEN  — Voice & Video calling
// ════════════════════════════════════════════════════════════════
class AgoraCallScreen extends StatefulWidget {
  final String channelName; // unique call ID (chatId works perfectly)
  final String friendName;
  final String friendPhoto;
  final String friendId;
  final bool isVideo;
  final bool isCaller; // true = I started the call

  const AgoraCallScreen({
    super.key,
    required this.channelName,
    required this.friendName,
    required this.friendPhoto,
    required this.friendId,
    required this.isVideo,
    required this.isCaller,
  });

  @override
  State<AgoraCallScreen> createState() => _AgoraCallScreenState();
}

class _AgoraCallScreenState extends State<AgoraCallScreen>
    with WidgetsBindingObserver {
  RtcEngine? _engine;
  bool _joined = false;
  bool _remoteJoined = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _cameraOff = false;
  bool _frontCamera = true;
  int? _remoteUid;
  int _callSeconds = 0;
  Timer? _callTimer;
  StreamSubscription? _callSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAgora();
    _listenForCallEvents();
  }

  // ── Listen for call status changes (accept / reject / end) ──
  void _listenForCallEvents() {
    final myId =
        widget.isCaller ? widget.friendId : 'caller'; // watch the right node
    // If I am caller, I watch the receiver's node to detect reject/accept
    _callSub = AgoraService.watchIncomingCall(widget.friendId).listen((event) {
      if (!mounted) return;
      final val = event.snapshot.value;
      if (val == null) {
        // Call was ended/cancelled by other side
        _endCall();
      } else if (val is Map && val['status'] == 'rejected') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call rejected.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        _endCall();
      }
    });
  }

  Future<void> _initAgora() async {
    // 1) Request permissions
    if (widget.isVideo) {
      await [Permission.microphone, Permission.camera].request();
    } else {
      await [Permission.microphone].request();
    }

    // 2) Create engine
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: AgoraService.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    // 3) Enable video if needed
    if (widget.isVideo) {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    } else {
      await _engine!.disableVideo();
    }

    // 4) Set up event handlers
    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (conn, elapsed) {
          if (mounted) setState(() => _joined = true);
        },
        onUserJoined: (conn, uid, elapsed) {
          if (mounted) {
            setState(() {
              _remoteUid = uid;
              _remoteJoined = true;
            });
            _startTimer();
          }
        },
        onUserOffline: (conn, uid, reason) {
          if (mounted) {
            setState(() {
              _remoteUid = null;
              _remoteJoined = false;
            });
          }
          _endCall();
        },
        onLeaveChannel: (conn, stats) {
          if (mounted) setState(() => _joined = false);
        },
      ),
    );

    // 5) Join channel
    await _engine!.joinChannel(
      token: AgoraService.token,
      channelId: widget.channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    // 6) Auto enable speaker for voice calls
    if (!widget.isVideo) {
      await _engine!.setEnableSpeakerphone(true);
    }
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  String get _callDuration {
    final m = (_callSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _endCall() async {
    _callTimer?.cancel();
    _callSub?.cancel();
    await AgoraService.endCall(widget.friendId);
    await _engine?.leaveChannel();
    await _engine?.release();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _engine?.muteLocalAudioStream(_muted);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    await _engine?.setEnableSpeakerphone(_speakerOn);
  }

  Future<void> _toggleCamera() async {
    setState(() => _cameraOff = !_cameraOff);
    await _engine?.muteLocalVideoStream(_cameraOff);
  }

  Future<void> _switchCamera() async {
    setState(() => _frontCamera = !_frontCamera);
    await _engine?.switchCamera();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _callSub?.cancel();
    _engine?.leaveChannel();
    _engine?.release();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ════════════════════════════════  UI  ════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff1a0a3d),
      body: widget.isVideo ? _buildVideoUI() : _buildVoiceUI(),
    );
  }

  // ── VOICE CALL UI ──
  Widget _buildVoiceUI() {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 60),
          // Friend avatar
          CircleAvatar(
            radius: 70,
            backgroundColor: Colors.white10,
            backgroundImage:
                widget.friendPhoto.isNotEmpty ? NetworkImage(widget.friendPhoto) : null,
            child: widget.friendPhoto.isEmpty
                ? Text(
                    widget.friendName[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(height: 24),
          Text(
            widget.friendName,
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            _remoteJoined
                ? _callDuration
                : widget.isCaller
                    ? 'Ringing...'
                    : 'Connecting...',
            style: TextStyle(
              color: _remoteJoined ? Colors.greenAccent : Colors.white60,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          // Controls
          _buildControls(isVideo: false),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  // ── VIDEO CALL UI ──
  Widget _buildVideoUI() {
    return Stack(
      children: [
        // Remote video (full screen)
        if (_remoteJoined && _remoteUid != null)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine!,
              canvas: VideoCanvas(uid: _remoteUid),
              connection: RtcConnection(channelId: widget.channelName),
            ),
          )
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.white10,
                  backgroundImage: widget.friendPhoto.isNotEmpty
                      ? NetworkImage(widget.friendPhoto)
                      : null,
                  child: widget.friendPhoto.isEmpty
                      ? Text(widget.friendName[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.bold))
                      : null,
                ),
                const SizedBox(height: 16),
                Text(widget.friendName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  widget.isCaller ? 'Ringing...' : 'Connecting...',
                  style: const TextStyle(color: Colors.white60, fontSize: 15),
                ),
              ],
            ),
          ),

        // Local video preview (small, top-right corner)
        if (widget.isVideo && _joined && !_cameraOff)
          Positioned(
            top: 60,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 100,
                height: 140,
                child: AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine!,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                ),
              ),
            ),
          ),

        // Duration badge
        if (_remoteJoined)
          Positioned(
            top: 60,
            left: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _callDuration,
                style:
                    const TextStyle(color: Colors.greenAccent, fontSize: 14),
              ),
            ),
          ),

        // Controls at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.only(bottom: 40, top: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: _buildControls(isVideo: true),
          ),
        ),
      ],
    );
  }

  // ── CALL CONTROL BUTTONS ──
  Widget _buildControls({required bool isVideo}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mute
        _controlBtn(
          icon: _muted ? Icons.mic_off : Icons.mic,
          label: _muted ? 'Unmute' : 'Mute',
          color: _muted ? Colors.redAccent : Colors.white24,
          onTap: _toggleMute,
        ),

        // Camera on/off (video only)
        if (isVideo)
          _controlBtn(
            icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
            label: _cameraOff ? 'Cam Off' : 'Cam On',
            color: _cameraOff ? Colors.redAccent : Colors.white24,
            onTap: _toggleCamera,
          ),

        // End Call
        _controlBtn(
          icon: Icons.call_end,
          label: 'End',
          color: Colors.redAccent,
          iconColor: Colors.white,
          size: 64,
          onTap: _endCall,
        ),

        // Speaker (voice only)
        if (!isVideo)
          _controlBtn(
            icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
            label: _speakerOn ? 'Speaker' : 'Earpiece',
            color: _speakerOn ? const Color(0xff38B6FF) : Colors.white24,
            onTap: _toggleSpeaker,
          ),

        // Flip camera (video only)
        if (isVideo)
          _controlBtn(
            icon: Icons.flip_camera_ios,
            label: 'Flip',
            color: Colors.white24,
            onTap: _switchCamera,
          ),
      ],
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required Color color,
    Color iconColor = Colors.white,
    double size = 56,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: size * 0.45),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  INCOMING CALL SCREEN — shown when someone calls you
// ════════════════════════════════════════════════════════════════
class IncomingCallScreen extends StatelessWidget {
  final String callerName;
  final String callerPhoto;
  final String callId;
  final String callerId;
  final String myId;
  final bool isVideo;

  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.callerPhoto,
    required this.callId,
    required this.callerId,
    required this.myId,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff1a0a3d),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Animated ring indicator
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white24,
                  width: 3,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38, width: 3),
                ),
                child: CircleAvatar(
                  radius: 65,
                  backgroundColor: Colors.white10,
                  backgroundImage: callerPhoto.isNotEmpty
                      ? NetworkImage(callerPhoto)
                      : null,
                  child: callerPhoto.isEmpty
                      ? Text(
                          callerName[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 50,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              callerName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isVideo ? Icons.videocam : Icons.phone,
                  color: Colors.white60,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
                  style: const TextStyle(color: Colors.white60, fontSize: 16),
                ),
              ],
            ),
            const Spacer(),
            // Accept / Reject buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Reject
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await AgoraService.rejectCall(myId);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.call_end,
                              color: Colors.white, size: 32),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Decline',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                  // Accept
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await AgoraService.acceptCall(myId);
                          if (context.mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AgoraCallScreen(
                                  channelName: callId,
                                  friendName: callerName,
                                  friendPhoto: callerPhoto,
                                  friendId: callerId,
                                  isVideo: isVideo,
                                  isCaller: false,
                                ),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isVideo ? Icons.videocam : Icons.phone,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Accept',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
