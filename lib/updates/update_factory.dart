import 'update_backend.dart';
import 'update_native.dart' if (dart.library.js_interop) 'update_web.dart';

UpdateBackend createUpdateBackend() => createPlatformUpdateBackend();
