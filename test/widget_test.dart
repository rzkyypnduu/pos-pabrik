import 'package:flutter_test/flutter_test.dart';
import 'package:pos_krupuk/main.dart';
import 'package:pos_krupuk/providers/backup_provider.dart';
import 'package:pos_krupuk/providers/sync_provider.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(PosKrupukApp(
      backupProvider: BackupProvider(),
      syncProvider: SyncProvider(),
    ));
    expect(find.text('POS Krupuk'), findsOneWidget);
  });
}
