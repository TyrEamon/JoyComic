import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/widgets/reader_image.dart';
import 'package:joycomic/views/reader/widgets/retry_for_image.dart';

/// Fake provider that immediately delivers a solid-color frame of known size.
class _SolidImageProvider extends ImageProvider<_SolidImageProvider> {
  _SolidImageProvider({required this.width, required this.height});

  final int width;
  final int height;

  @override
  Future<_SolidImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_SolidImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _SolidImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_build());
  }

  Future<ImageInfo> _build() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFF0000),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    return ImageInfo(image: image, scale: 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is _SolidImageProvider &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'decoded RawImage keeps non-zero height under vertical list constraints',
    (tester) async {
      // 960x1355 mirrors the real JM first-frame log (comic 1452786).
      const pixelW = 960;
      const pixelH = 1355;
      const viewportW = 390.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox(
              width: viewportW,
              height: 800,
              // Mimic VerticalList: full-width column with unbounded height scroll.
              child: ListView(
                children: [
                  RetryForImage(
                    fadeDuration: Duration.zero,
                    imageProvider: _SolidImageProvider(
                      width: pixelW,
                      height: pixelH,
                    ),
                    builder: (context, status) {
                      final frame = status.imageInfo;
                      if (frame == null) {
                        return const SizedBox(
                          width: viewportW,
                          height: viewportW / (3 / 4),
                          child: ColoredBox(color: Colors.grey),
                        );
                      }
                      final aspect = pixelW / pixelH;
                      final height = (viewportW / aspect).ceilToDouble();
                      return SizedBox(
                        width: viewportW,
                        height: height,
                        child: RawImage(
                          image: frame.image,
                          scale: frame.scale,
                          width: viewportW,
                          height: height,
                          fit: BoxFit.fitWidth,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Allow OneFrameImageStreamCompleter to resolve.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final raw = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
      expect(raw, isNotEmpty, reason: 'decoded frame must paint via RawImage');
      final painted = raw.first;
      expect(painted.image, isNotNull);
      expect(painted.width, viewportW);
      expect(painted.height, greaterThan(100));
      // 390 / (960/1355) ≈ 550.7 → ceil 551
      expect(painted.height, closeTo(551, 1));

      final size = tester.getSize(find.byType(RawImage).first);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(100));
    },
  );

  testWidgets(
    'ReaderImage default fit is fitWidth for vertical continuous mode',
    (tester) async {
      // Structural guard: fitWidth is required so pages fill the list width
      // instead of containing into a zero-height box under some parents.
      const image = ReaderImage(url: 'https://example.com/a.webp');
      expect(image.fit, BoxFit.fitWidth);
    },
  );
}
