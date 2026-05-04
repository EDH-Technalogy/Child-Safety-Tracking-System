import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool get isGoogleMapsJsAvailable {
  try {
    final google = globalContext.getProperty<JSAny?>('google'.toJS);
    if (google == null || google.isUndefinedOrNull) {
      return false;
    }

    final maps = (google as JSObject).getProperty<JSAny?>('maps'.toJS);
    return maps != null && !maps.isUndefinedOrNull;
  } catch (_) {
    return false;
  }
}
