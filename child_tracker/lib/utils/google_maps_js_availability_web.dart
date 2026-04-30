import 'dart:html' as html;
import 'dart:js_util' as js_util;

bool get isGoogleMapsJsAvailable {
  try {
    if (!js_util.hasProperty(html.window, 'google')) {
      return false;
    }

    final google = js_util.getProperty<Object?>(html.window, 'google');
    if (google == null) {
      return false;
    }

    return js_util.hasProperty(google, 'maps');
  } catch (_) {
    return false;
  }
}
