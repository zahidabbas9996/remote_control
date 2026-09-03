import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/main.dart';

void main() {
  testWidgets('renders the remote control home screen', (tester) async {
    await tester.pumpWidget(const RemoteControlApp());

    expect(find.text('Remote Control'), findsOneWidget);
    expect(find.text('Viewer mode'), findsOneWidget);
    expect(find.text('Host connection ID'), findsOneWidget);
  });
}