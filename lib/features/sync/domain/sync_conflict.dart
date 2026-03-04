class SyncConflict {
  final String path; // Original path
  final String conflictPath; // Remote path with .sync-conflict-
  final DateTime localTime;
  final DateTime remoteTime;
  final int localSize;
  final int remoteSize;

  SyncConflict({
    required this.path,
    required this.conflictPath,
    required this.localTime,
    required this.remoteTime,
    required this.localSize,
    required this.remoteSize,
  });
}
