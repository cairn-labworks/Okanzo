---
description: Preserve phone app data when installing Android builds or running device integration tests.
applyTo: 'integration_test/**,test_driver/**,android/**'
---

# Physical-device testing

Before using Flutter's installer, check the installed debug version code and run `adb -s <device> install -r <apk>` with an equal-or-higher build number; stop on a signing mismatch and never uninstall or clear data without explicit approval. Flutter can automatically uninstall and retry after an incompatible update, so build number alone does not protect data. Always pass `--keep-app-running` to `flutter drive --use-application-binary <apk> --driver test_driver/simple_net_worth.dart`: by default, drive uninstalls the app after the test, even on failure. After testing, rebuild `lib/main.dart`, install it with `adb install -r`, launch and verify the normal app, and leave it installed; see the physical-device section of the README.
