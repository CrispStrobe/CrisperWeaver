// §12.6b — Conditional OCR import.
// On native, exports the real CrispEmbed OCR classes.
// On web, exports stubs that throw UnsupportedError.
export 'package:crispembed/crispembed.dart'
    if (dart.library.js_interop) 'ocr_stub.dart';
