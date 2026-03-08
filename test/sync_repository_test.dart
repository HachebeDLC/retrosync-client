import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vaultsync_client/features/sync/data/sync_repository.dart';
import 'package:vaultsync_client/core/services/api_client.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late SyncRepository repository;
  late MockApiClient mockApiClient;

  setUp(() {
    mockApiClient = MockApiClient();
    repository = SyncRepository(mockApiClient);
  });

  group('SyncRepository Error Handling', () {
    test('syncSystem should call onError when API fails', () async {
      when(() => mockApiClient.get('/api/v1/files'))
          .thenThrow(Exception('Network error'));

      String? lastError;
      await repository.syncSystem(
        'ps2', 
        '/storage/emulated/0/PS2',
        onError: (err) => lastError = err,
      );

      expect(lastError, contains('Network error'));
    });
  });
}
