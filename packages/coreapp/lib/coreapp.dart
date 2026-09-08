// coreapp — shared plugin for every game plugin: API client, SignalR,
// connectivity/reconnection handling, storage, and base
// presentation widgets. Contains no game-specific logic.
library coreapp;


// Public Game Engine API — the native integration boundary.
export 'engine/game_engine.dart';
export 'engine/game_engine_channel.dart';
export 'engine/game_engine_config.dart';
export 'engine/game_engine_connection_state.dart';
export 'engine/game_engine_host.dart';
export 'engine/game_engine_root.dart';
export 'engine/game_engine_runtime.dart';
// base
export 'base/base_repository.dart';
export 'base/base_usecase.dart';
export 'base/failure.dart';
export 'base/result.dart';

// network
export 'network/api_client.dart';
export 'network/api_exception.dart';
export 'network/api_headers_builder.dart';
export 'network/api_response_handler.dart';
export 'network/json_value.dart';
export 'network/models/api_error_model.dart';
export 'network/models/api_response.dart';
export 'network/network_info.dart';
export 'network/network_info_provider.dart';

// signalr
export 'signalr/signalr_provider.dart';
export 'signalr/signalr_service.dart';
export 'signalr/signalr_status.dart';

// connectivity
export 'connectivity/connection_recovery_controller.dart';

// storage
export 'storage/prefs_keys.dart';
export 'storage/shared_prefs_service.dart';
export 'storage/shared_prefs_service_impl.dart';

// security
export 'security/security_generator.dart';

// constants
export 'constants/api_endpoints.dart';
export 'constants/app_assets.dart';
export 'constants/app_colors.dart';
export 'constants/app_fonts.dart';
export 'constants/app_language.dart';
export 'constants/app_sounds.dart';

// audio
export 'audio/audio_provider.dart';
export 'audio/audio_service.dart';
export 'audio/audio_source_type.dart';
export 'l10n/app_strings.dart';
export 'l10n/ar_app_strings.dart';
export 'l10n/en_app_strings.dart';

// di
export 'di/providers.dart';

// utils
export 'utils/app_lifecycle_observer.dart';
export 'utils/app_logger.dart';
export 'utils/app_share.dart';
export 'utils/app_email.dart';
export 'utils/app_url.dart';
export 'utils/post_frame.dart';

// presentation
export 'presentation/app_theme.dart';
export 'presentation/base_dialog.dart';
export 'presentation/base_page.dart';
export 'presentation/base_sheet.dart';
export 'presentation/hub_event_mixin.dart';
export 'presentation/providers/app_language_provider.dart';
export 'presentation/providers/connection_loader_provider.dart';
export 'presentation/providers/loader_provider.dart';
export 'presentation/ui_helpers_interface.dart';
export 'presentation/widgets/app_icon_button.dart';
export 'presentation/widgets/app_image_view.dart';
export 'presentation/widgets/app_skeleton.dart';
export 'presentation/widgets/countdown_timer_text.dart';
export 'presentation/widgets/app_scaffold.dart';
export 'presentation/widgets/app_text_field.dart';
export 'presentation/widgets/app_text_view.dart';
export 'presentation/widgets/app_toolbar.dart';
export 'presentation/widgets/game_button.dart';
export 'presentation/widgets/game_dialog.dart';
export 'presentation/widgets/show_dialog_game.dart';
export 'presentation/widgets/app_lottie_view.dart';
export 'presentation/widgets/app_throb.dart';
export 'presentation/widgets/base_loader.dart';
export 'presentation/widgets/connection_loader.dart';
export 'presentation/widgets/loader_overlay.dart';

// auth feature
export 'features/auth/domain/entities/auth_session.dart';
export 'features/auth/domain/repositories/auth_repository.dart';
export 'features/auth/domain/usecases/login_usecase.dart';
export 'features/auth/presentation/providers/auth_notifier.dart';
export 'features/auth/presentation/providers/auth_providers.dart';
