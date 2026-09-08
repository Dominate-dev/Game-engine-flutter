import 'package:flutter_test/flutter_test.dart';
import 'package:coreapp/coreapp.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('setToken / getToken uses the default key', () async {
    final prefs = await SharedPrefsService.init();

    await prefs.setToken(value: 'textAAA');

    expect(prefs.getToken(), 'textAAA');
  });

  test('setJson / getJson stores an object map', () async {
    final prefs = await SharedPrefsService.init();

    await prefs.setJson('profile', {'id': '42', 'name': 'hasan'});

    expect(prefs.getJson('profile'), {'id': '42', 'name': 'hasan'});
  });

  test('clearAuth removes token and user id', () async {
    final prefs = await SharedPrefsService.init();
    await prefs.setToken(value: 'textAAA');
    await prefs.setUserId(value: '1');

    await prefs.clearAuth();

    expect(prefs.getToken(), isNull);
    expect(prefs.getUserId(), 0);
  });
}
