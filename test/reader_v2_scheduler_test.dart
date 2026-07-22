import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader_v2/core/reader_v2_scheduler.dart';
import 'package:joycomic/views/reader_v2/core/reader_v2_session.dart';

void main() {
  test('scheduler never exceeds configured concurrency', () async {
    final session = ReaderV2Session(traceId: 'limit');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 3);
    var active = 0;
    var maxActive = 0;
    final gates = List.generate(6, (_) => Completer<void>());

    final jobs = List.generate(6, (index) {
      return scheduler.schedule<int>(
        key: 'p$index',
        page: index,
        priority: ReaderV2Priority.preload,
        task: () async {
          active += 1;
          if (active > maxActive) maxActive = active;
          await gates[index].future;
          active -= 1;
          return index;
        },
      );
    });

    await Future<void>.delayed(Duration.zero);
    expect(scheduler.activeCount, 3);
    expect(maxActive, 3);
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
      await Future<void>.delayed(Duration.zero);
    }
    expect(await Future.wait(jobs), [0, 1, 2, 3, 4, 5]);
    expect(maxActive, 3);
  });

  test('visible jobs run before queued preload jobs', () async {
    final session = ReaderV2Session(traceId: 'priority');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    final gate = Completer<void>();
    final order = <int>[];

    final first = scheduler.schedule<void>(
      key: 'first',
      page: 0,
      priority: ReaderV2Priority.visible,
      task: () async {
        order.add(0);
        await gate.future;
      },
    );
    final distant = scheduler.schedule<void>(
      key: 'distant',
      page: 20,
      priority: ReaderV2Priority.preload,
      task: () async => order.add(20),
    );
    final visible = scheduler.schedule<void>(
      key: 'visible',
      page: 1,
      priority: ReaderV2Priority.visible,
      task: () async => order.add(1),
    );

    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([first, distant, visible]);
    expect(order, [0, 1, 20]);
  });

  test('duplicate cache keys share one task', () async {
    final session = ReaderV2Session(traceId: 'dedupe');
    final scheduler = ReaderV2Scheduler(session: session);
    var calls = 0;

    Future<int> load() => scheduler.schedule<int>(
      key: 'same',
      page: 0,
      priority: ReaderV2Priority.visible,
      task: () async {
        calls += 1;
        return 42;
      },
    );

    final values = await Future.wait([load(), load()]);
    expect(values, [42, 42]);
    expect(calls, 1);
  });

  test('cancelling a session rejects active and queued results', () async {
    final session = ReaderV2Session(traceId: 'cancel');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    final gate = Completer<void>();

    final active = scheduler.schedule<int>(
      key: 'active',
      page: 0,
      priority: ReaderV2Priority.visible,
      task: () async {
        await gate.future;
        return 1;
      },
    );
    final queued = scheduler.schedule<int>(
      key: 'queued',
      page: 1,
      priority: ReaderV2Priority.preload,
      task: () async => 2,
    );
    final activeCancelled = expectLater(
      active,
      throwsA(isA<ReaderV2Cancelled>()),
    );
    final queuedCancelled = expectLater(
      queued,
      throwsA(isA<ReaderV2Cancelled>()),
    );

    await Future<void>.delayed(Duration.zero);
    session.cancel('route disposed');
    gate.complete();

    await activeCancelled;
    await queuedCancelled;
    expect(session.events.where((event) => event.stage == 'cancel').length, 1);
  });
}
