# Remote Control

An Android Flutter app that shares the host screen over WebRTC and sends
viewer touch input back through an Android Accessibility Service.

## Run

1. Install Flutter 3.24 or newer and Android Studio.
2. From this directory, run `flutter pub get`.
3. Connect an Android 7.0+ device or start an emulator.
4. Run `flutter run`.
5. On the host device, choose **Host**, start screen sharing, and enable the
   Accessibility Service when prompted.
6. On the viewer device, choose **Viewer**, paste the host connection ID, and
   connect.

## Important Android permissions

Screen sharing uses Android MediaProjection and the viewer control path uses
the `flutter_accessibility_service` plugin. Android displays a system prompt
for screen sharing, while Accessibility permission must be enabled manually in
Android Settings.

The app uses PeerJS's public signaling server at `0.peerjs.com`. The media
stream and touch messages are peer-to-peer after signaling; production use
should move signaling to an owned PeerServer and add authenticated pairing.