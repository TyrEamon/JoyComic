/// One-tap diagnostic log export to a shareable TXT file.
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'log.dart';

/// Export all persisted logs as a `.txt` file and open the system share sheet.
///
/// Returns `true` when a file was produced and handed to the share sheet,
/// `false` when there is nothing to export. Throws on I/O or share failures.
Future<bool> exportJoyComicLogsTxt({
  BuildContext? context,
  String? note,
  Rect? sharePositionOrigin,
}) async {
  final file = await Log.writeExportTxtFile(note: note);
  if (file == null) return false;

  Rect? origin = sharePositionOrigin;
  if (origin == null && context != null && context.mounted) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
  }

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/plain', name: file.uri.pathSegments.last)],
    subject: 'JoyComic 诊断日志',
    text: 'JoyComic 诊断日志（TXT）',
    sharePositionOrigin: origin,
    fileNameOverrides: [file.uri.pathSegments.last],
  );
  return true;
}
