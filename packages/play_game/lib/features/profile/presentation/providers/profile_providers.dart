import 'package:coreapp/coreapp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/profile_remote_datasource.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/usecases/get_public_profile_usecase.dart';

// Temporary id used by lobby screens until the hub sends a real player id.
const testPublicProfileId = 47;

final profileRemoteDataSourceProvider = Provider<ProfileRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ProfileRemoteDataSourceImpl(apiClient);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final dataSource = ref.watch(profileRemoteDataSourceProvider);
  return ProfileRepositoryImpl(dataSource);
});

final getPublicProfileUseCaseProvider = Provider<GetPublicProfileUseCase>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return GetPublicProfileUseCase(repository);
});

final publicProfileProvider = StateProvider<UserProfile?>((ref) => null);
