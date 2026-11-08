import 'drive_native.dart'
    if (dart.library.js_interop) 'drive_web.dart'
    as platform;
import 'drive_gateway.dart';

DriveGateway createDriveGateway() =>
    DriveGateway(platform: platform.createDrivePlatform());
