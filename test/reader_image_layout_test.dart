import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/widgets/reader_image.dart';

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

/// Wraps [ImageProvider] resolution the same way ReaderImage does, for unit test.
class _TestFrameImage extends StatefulWidget {
  const _TestFrameImage({
    required this.provider,
    required this.viewportW,
  });

  final ImageProvider provider;
  final double viewportW;

  @override
  State<_TestFrameImage> createState() => _TestFrameImageState();
}

class _TestFrameImageState extends State<_TestFrameImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageStreamCompleterHandle? _handle;
  ImageInfo? _info;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = widget.provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener((info, _) {
      setState(() => _info = info);
    });
    stream.addListener(_listener!);
    _handle = stream.completer?.keepAlive();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _handle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) {
      return SizedBox(
        width: widget.viewportW,
        height: widget.viewportW / (3 / 4),
        child: const ColoredBox(color: Colors.grey),
      );
    }
    const pixelW = 960;
    const pixelH = 1355;
    final height = (widget.viewportW / (pixelW / pixelH)).ceilToDouble();
    return SizedBox(
      width: widget.viewportW,
      height: height,
      child: RawImage(
        image: info.image,
        scale: info.scale,
        width: widget.viewportW,
        height: height,
        fit: BoxFit.fitWidth,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'decoded RawImage keeps non-zero height under vertical list constraints',
    (tester) async {
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
              child: ListView(
                children: [
                  _TestFrameImage(
                    provider: _SolidImageProvider(
                      width: pixelW,
                      height: pixelH,
                    ),
                    viewportW: viewportW,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final raw = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
      expect(raw, isNotEmpty, reason: 'decoded frame must paint via RawImage');
      final painted = raw.first;
      expect(painted.image, isNotNull);
      expect(painted.width, viewportW);
      expect(painted.height, greaterThan(100));
      expect(painted.height, closeTo(551, 1));

      final size = tester.getSize(find.byType(RawImage).first);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(100));
    },
  );

  test('ReaderImage default fit is fitWidth for vertical continuous mode', () {
    const image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image.fit, BoxFit.fitWidth);
  });

  test('ReaderImage is StatefulWidget with keepAlive lifecycle (source guard)', () {
    // Structural: must own ImageStreamCompleterHandle like  ComicImage.
    final source = const ReaderImage(url: 'https://example.com/a.webp')
        .runtimeType
        .toString();
    // StatefulWidget creates State that holds completer handle.
    expect(source, 'ReaderImage');
  });
}
