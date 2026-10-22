import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [text] as a file named [name].
bool saveTextFile(String name, String text, String mime) {
  final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: '$mime;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  (web.HTMLAnchorElement()
        ..href = url
        ..download = name)
      .click();
  web.URL.revokeObjectURL(url);
  return true;
}

const canPickFile = true;

/// Opens the browser's file chooser and returns the chosen text file (UTF-8, else Latin-1 as many banks write).
Future<String?> pickTextFile() {
  final done = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,.txt,text/csv,text/plain';
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      done.complete(null);
      return;
    }
    file.arrayBuffer().toDart.then((buf) {
      final bytes = buf.toDart.asUint8List();
      try {
        done.complete(utf8.decode(bytes));
      } on FormatException {
        done.complete(latin1.decode(bytes));
      }
    }, onError: (_) => done.complete(null));
  }).toJS;
  input.click();
  return done.future;
}
