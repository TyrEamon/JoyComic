import '../reader/reader.dart';

class ReaderV2 extends Reader {
  const ReaderV2({
    super.key,
    required super.comicState,
    super.imageLoader,
    super.readRecordHelper,
    super.readRecordDebounce,
  });
}
