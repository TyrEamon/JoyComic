import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_endpoint_health.dart';

void main() {
  test('failed host is cooled down and successful host is first', () {
    final health = JmEndpointHealth(
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
      baseCooldown: const Duration(seconds: 10),
    );
    health.recordFailure('dead.example', FailureClass.timeout);
    expect(health.order(const ['dead.example', 'ok.example']), [
      'ok.example',
      'dead.example',
    ]);
    health.recordSuccess('dead.example');
    expect(
      health.order(const ['dead.example', 'ok.example']).first,
      'dead.example',
    );
  });

  test('same probe key shares one future', () async {
    final health = JmEndpointHealth();
    var calls = 0;
    Future<int> probe() async {
      calls++;
      return 7;
    }

    final values = await Future.wait([
      health.singleFlight('login-probe', probe),
      health.singleFlight('login-probe', probe),
    ]);
    expect(values, [7, 7]);
    expect(calls, 1);
  });

  test('401 business response does not cool the host', () {
    final health = JmEndpointHealth(
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
      baseCooldown: const Duration(seconds: 10),
    );
    health.recordBusinessResponse('one.example', statusCode: 401);
    expect(health.isCoolingDown('one.example'), isFalse);
    expect(
      health.order(const ['one.example', 'two.example']).first,
      'one.example',
    );
  });

  test('decoded business error does not cool the host', () {
    final health = JmEndpointHealth(
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
      baseCooldown: const Duration(seconds: 10),
    );
    health.recordBusinessResponse(
      'biz.example',
      statusCode: 200,
      isBusinessError: true,
    );
    expect(health.isCoolingDown('biz.example'), isFalse);
  });

  test('cooldown uses exponential backoff capped at 60 seconds', () {
    var now = DateTime.fromMillisecondsSinceEpoch(0);
    final health = JmEndpointHealth(
      clock: () => now,
      baseCooldown: const Duration(seconds: 10),
    );

    health.recordFailure('host.example', FailureClass.network);
    expect(health.isCoolingDown('host.example'), isTrue);

    now = now.add(const Duration(seconds: 10));
    expect(health.isCoolingDown('host.example'), isFalse);

    health.recordFailure('host.example', FailureClass.timeout);
    // 2nd failure: 20s
    now = now.add(const Duration(seconds: 19));
    expect(health.isCoolingDown('host.example'), isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(health.isCoolingDown('host.example'), isFalse);

    // Drive failures until cap: 10, 20, 40, 60, 60...
    for (var i = 0; i < 5; i++) {
      health.recordFailure('host.example', FailureClass.serverError);
    }
    now = now.add(const Duration(seconds: 59));
    expect(health.isCoolingDown('host.example'), isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(health.isCoolingDown('host.example'), isFalse);
  });

  test(
    'singleFlight removes completed entries so a later call runs again',
    () async {
      final health = JmEndpointHealth();
      var calls = 0;
      Future<int> probe() async {
        calls++;
        return calls;
      }

      expect(await health.singleFlight('k', probe), 1);
      expect(await health.singleFlight('k', probe), 2);
      expect(calls, 2);
    },
  );
}
