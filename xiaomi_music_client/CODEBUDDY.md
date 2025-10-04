Prefix: Terminal Assistant Agent configuration for this repository.

Commands
- Install deps: flutter pub get
- Lint/analyze: flutter analyze
- Format: dart format .
- Generate code (json_serializable/riverpod): dart run build_runner build --delete-conflicting-outputs
- Watch codegen: dart run build_runner watch --delete-conflicting-outputs
- Run (web): flutter run -d chrome
- Run (mobile): flutter run
- Run (macOS): flutter run -d macos
- Tests (all): flutter test
- Tests (single file): flutter test path/to/test.dart
- Build APK (release): flutter build apk --release
- Build iOS (release): flutter build ios --release
- Build macOS (release): flutter build macos --release

Architecture overview
- App shell: lib/main.dart boots ProviderScope and MaterialApp.router with routerConfig from app_router.dart. Global system UI tuned; FlutterError filtered for known non-critical web/layout issues.
- Routing: GoRouter via appRouterProvider in lib/app_router.dart:line_16. Root renders AuthWrapper which redirects based on auth state. Named routes cover settings, downloads, now playing, JS proxy test.
- State management: Riverpod providers in lib/presentation/providers/*.dart drive UI. Key providers: auth_provider.dart, device_provider.dart, playback_provider.dart, music_search_provider.dart, music_library_provider.dart, playlist_provider.dart, js_* providers wiring JS runtime and sources, dio_provider.dart for HTTP client provisioning.
- Clean Architecture layering (per README):
  - core/: cross-cutting concerns. constants/app_constants.dart for timeouts; errors/app_exception.dart with typed exceptions; core/network/dio_client.dart centralizes Dio with Basic Auth and error mapping.
  - data/: concrete services and adapters. services/ includes music_api_service.dart for backend endpoints, unified_api_service.dart for third-party music search/playback, playback_strategy.dart with local/remote strategies, JS runtime/source services (unified_js_runtime_service.dart, js_proxy_executor_service.dart, enhanced_js_proxy_executor_service.dart, local_js_source_service.dart, webview_js_source_service.dart), native_music_search_service.dart. adapters/ map API payloads to domain models (music_list_adapter.dart, playlist_adapter.dart, search_adapter.dart, json adapters). models/ define DTOs (music.dart, playlist.dart, playing_music.dart, device.dart, online_music_result.dart, js_script.dart).
  - domain/: business contracts (entities/, repositories/). UI depends on domain abstractions; data layer implements them. Consult lib/domain/* when adding new features.
  - presentation/: UI pages and widgets. pages/ include login, main, now_playing, control_panel, music_search, music_library, playlist and settings subpages. widgets/ include mini_player, music_list_item, app_snackbar, auth_wrapper, layout utilities.
- Networking: core/network/dio_client.dart builds a Dio per-server with Basic Auth header and robust error translation to AppException subclasses. Use this client via providers to ensure credentials and baseUrl are consistent.
- Audio: just_audio + audio_session used in playback flows (see mini_player.dart and playback_provider.dart) to control and reflect play state.
- JS runtime integration: UnifiedJsRuntimeService pre-initialized at startup (main.dart:lines_12-18) to support JS-based source adapters and proxy execution via js_proxy_executor_service.dart and enhanced_js_proxy_executor_service.dart. Source services choose between local_js_source_service.dart and webview_js_source_service.dart.
- External unified music API: data/services/unified_api_service.dart talks to music.txqq.pro for cross-platform search and URL resolution with custom headers and plain-response JSON parsing; results mapped to OnlineMusicResult and consumed by search/playback providers.

Conventions
- Run build_runner after changing json_serializable models or Riverpod generators.
- Keep provider wiring in presentation/providers; services live under data/services; core-only utilities under core/.
- Add new routes via appRouterProvider and expose pages under presentation/pages; guard with AuthWrapper when needed.

Notes from README
- Framework: Flutter 3.7+, Riverpod, Dio, Material 3, cached_network_image, shared_preferences; targets Web/iOS/Android/macOS.
- API endpoints the app expects from server: /getversion, /playingmusic, /cmd, /playmusic, /getvolume, /setvolume, /getsetting, /musiclist, /searchmusic, /delmusic, /musicinfo, /playlistnames, /playlistmusics, /playmusiclist, /playlistadd, /playlistdel.

Quick file refs
- Router setup: lib/app_router.dart:16
- App entry: lib/main.dart:9
- HTTP client: lib/core/network/dio_client.dart:7
- Unified music API: lib/data/services/unified_api_service.dart:7
- Providers: lib/presentation/providers/*.dart
- UI pages: lib/presentation/pages/*.dart
- Models: lib/data/models/*.dart
- Adapters: lib/data/adapters/*.dart
- JS runtime: lib/data/services/unified_js_runtime_service.dart:7
