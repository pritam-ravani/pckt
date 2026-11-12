import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_info.dart';

/// Adds the app's own licence and the bundled fonts' licences to the page
/// opened by showLicensePage, next to the packages Flutter lists itself.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([AppInfo.name, 'Pckt'], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks(['Inter font'], await rootBundle.loadString('assets/google_fonts/OFL-Inter.txt'));
    yield LicenseEntryWithLineBreaks([
      'Manrope font',
    ], await rootBundle.loadString('assets/google_fonts/OFL-Manrope.txt'));
  });
}
