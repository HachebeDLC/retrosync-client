import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final baseUrlProvider = FutureProvider<String?>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getBaseUrl();
});
