import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/services/push_toggle_controller.dart';

/// The Push Notifications switch: on only when the account wants pushes and
/// the phone allows them, and it behaves like a real app's when the phone says
/// no.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool server;
  late PushOsState phone;
  late int requests;
  late int settingsOpened;
  late int registered;
  late bool failSave;

  PushToggleController make() => PushToggleController(
        loadServer: () async => server,
        saveServer: (v) async {
          if (failSave) throw Exception('offline');
          server = v;
        },
        osState: () async => phone,
        requestOs: () async {
          requests++;
          return phone;
        },
        openSettings: () async => settingsOpened++,
        registerDevice: () async => registered++,
      );

  setUp(() {
    server = true;
    phone = PushOsState.allowed;
    requests = 0;
    settingsOpened = 0;
    registered = 0;
    failSave = false;
  });

  test('shows on only when both the account and the phone allow it', () async {
    final c = make();
    await c.load();
    expect(c.enabled, isTrue);

    phone = PushOsState.blocked;
    await c.load();
    expect(c.enabled, isFalse);
    expect(c.blockedByPhone, isTrue);

    phone = PushOsState.allowed;
    server = false;
    await c.load();
    expect(c.enabled, isFalse);
    expect(c.statusText, 'Off');
  });

  test('turning off saves to the server', () async {
    final c = make();
    await c.load();
    final error = await c.setEnabled(false, askToOpenSettings: () async => false);
    expect(error, isNull);
    expect(server, isFalse);
    expect(c.enabled, isFalse);
  });

  test('turning on when never asked shows the system prompt, then saves and registers the phone', () async {
    server = false;
    phone = PushOsState.notAsked;
    final c = make();
    await c.load();

    // The person taps Allow on the system prompt.
    phone = PushOsState.notAsked;
    final prompt = c.setEnabled(true, askToOpenSettings: () async => false);
    phone = PushOsState.allowed; // requestPermission returns this
    await prompt;
    await Future<void>.delayed(Duration.zero);

    expect(requests, 1);
    expect(server, isTrue);
    expect(c.enabled, isTrue);
    expect(registered, 1);
  });

  test('blocked by the phone: offers settings, and finishes turning on when they come back allowed', () async {
    server = false;
    phone = PushOsState.blocked;
    final c = make();
    await c.load();

    var asked = 0;
    await c.setEnabled(true, askToOpenSettings: () async {
      asked++;
      return true;
    });
    expect(asked, 1);
    expect(settingsOpened, 1);
    expect(server, isFalse, reason: 'nothing is saved until the phone allows it');

    phone = PushOsState.allowed;
    await c.refreshFromPhone();
    expect(server, isTrue);
    expect(c.enabled, isTrue);
  });

  test('"Not now" leaves everything as it was', () async {
    server = false;
    phone = PushOsState.blocked;
    final c = make();
    await c.load();

    await c.setEnabled(true, askToOpenSettings: () async => false);
    expect(settingsOpened, 0);
    expect(server, isFalse);

    phone = PushOsState.allowed;
    await c.refreshFromPhone();
    expect(server, isFalse, reason: 'they did not ask to turn it on');
  });

  test('a failed save puts the switch back and reports it', () async {
    final c = make();
    await c.load();
    failSave = true;

    final error = await c.setEnabled(false, askToOpenSettings: () async => false);
    expect(error, isNotNull);
    expect(c.enabled, isTrue);
  });
}
