import 'package:flutter_test/flutter_test.dart';
import 'package:pos_krupuk/constants/formatters.dart';
import 'package:pos_krupuk/models/saldo_deduction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RupiahInputFormatter decimals', () {
    RupiahInputFormatter formatter() => RupiahInputFormatter(allowDecimal: true);

    TextEditingValue format(String input) {
      return formatter()
          .formatEditUpdate(const TextEditingValue(), TextEditingValue(text: input));
    }

    test('keeps comma decimal', () {
      expect(format('18000,5').text, '18.000,5');
    });

    test('dot is treated as thousands separator', () {
      expect(format('20.000').text, '20.000');
      expect(format('20000').text, '20.000');
    });

    test('whole number never gains a comma', () {
      expect(format('20000').text.contains('2,0'), isFalse);
      expect(format('20000').text.contains(','), isFalse);
    });

    test('does not mangle whole thousands', () {
      expect(format('1800000').text, '1.800.000');
    });

    test('truncates to one decimal', () {
      expect(format('18000,56').text, '18.000,5');
    });

    test('leading comma makes zero decimal', () {
      expect(format(',5').text, '0,5');
    });
  });

  group('parse & re-format helpers', () {
    test('parseNumInput parses comma decimal', () {
      expect(parseNumInput('18.000,5'), 18000.5);
    });

    test('parseNumInput parses plain integer', () {
      expect(parseNumInput('18000'), 18000);
    });

    test('rupiahInputText formats decimal', () {
      expect(rupiahInputText(18000.5), '18.000,5');
    });

    test('rupiahInputText formats whole', () {
      expect(rupiahInputText(18000), '18.000');
    });
  });

  group('SaldoDeduction model', () {
    test('result keeps decimals', () {
      final sd = SaldoDeduction(a: 18000.5, b: 5.5);
      expect(sd.result, 17995.0);
    });

    test('fromMap keeps decimals', () {
      final sd = SaldoDeduction.fromMap({'a': 18000.5, 'b': 5.5});
      expect(sd.a, 18000.5);
      expect(sd.b, 5.5);
      expect(sd.result, 17995.0);
    });
  });

  group('SQLite integer-affinity column', () {
    late Database db;

    setUpAll(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE saldo_deductions (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, a INTEGER DEFAULT 0, b INTEGER DEFAULT 0)',
      );
    });

    tearDownAll(() => db.close());

    test('stores and reads back decimals', () async {
      await db.insert('saldo_deductions', {'date': '2026-09-10', 'a': 18000.5, 'b': 5.5});
      final rows = await db.query('saldo_deductions');
      final a = rows.first['a'] as num;
      final b = rows.first['b'] as num;
      expect(a.toDouble(), 18000.5);
      expect(b.toDouble(), 5.5);
    });
  });
}