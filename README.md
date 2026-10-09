# Set Notes
Offline workout notebook from user queue idea-995b500e196c.

Flutter 3.47.5. Tests: flutter analyze; flutter test test; flutter drive --no-start-paused --driver=test_driver/screenshots.dart --target=integration_test/native_flow_test.dart.
Production Android banner: --dart-define=ADMOB_BANNER_ID=ca-app-pub-2803803669720807/8950258409. iOS banner: --dart-define=ADMOB_BANNER_ID=ca-app-pub-2803803669720807/8911653392. Signing secrets stay outside source.

iOS scheduled execution is preparation-only. ios-release.yml signs/exports into a private draft artifact; it contains no Apple upload step. Actual Apple upload/review/publication requires a separate direct app/version approval.
