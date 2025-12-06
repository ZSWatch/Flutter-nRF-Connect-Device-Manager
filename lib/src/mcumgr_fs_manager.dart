part of mcumgr_flutter;

// ============================================================================
// Download Callbacks
// ============================================================================

sealed class DownloadCallback {
  String path;

  DownloadCallback(this.path);
}

class OnDownloadProgressChanged extends DownloadCallback {
  final int current;
  final int total;
  final int timestamp;
  OnDownloadProgressChanged(super.path, this.current, this.total, this.timestamp);
}

class OnDownloadFailed extends DownloadCallback {
  final String? cause;
  OnDownloadFailed(super.path, this.cause);
}

class OnDownloadCancelled extends DownloadCallback {
  OnDownloadCancelled(super.path);
}

class OnDownloadCompleted extends DownloadCallback {
  final Uint8List data;
  OnDownloadCompleted(super.path, this.data);
}

// ============================================================================
// Upload Callbacks
// ============================================================================

sealed class UploadCallback {
  String path;

  UploadCallback(this.path);
}

class OnUploadProgressChanged extends UploadCallback {
  final int current;
  final int total;
  final int timestamp;
  OnUploadProgressChanged(super.path, this.current, this.total, this.timestamp);
}

class OnUploadFailed extends UploadCallback {
  final String? cause;
  OnUploadFailed(super.path, this.cause);
}

class OnUploadCancelled extends UploadCallback {
  OnUploadCancelled(super.path);
}

class OnUploadCompleted extends UploadCallback {
  OnUploadCompleted(super.path);
}

// ============================================================================
// FsManager Interface
// ============================================================================

abstract class FsManager {
  late final String remoteId;

  // _cache is library-private, thanks to
  // the _ in front of its name.
  static final Map<String, FsManager> _cache = <String, FsManager>{};

  factory FsManager(String remoteId) {
    return _cache.putIfAbsent(remoteId, () => _FsManagerImpl._internal(remoteId));
  }

  Stream<DownloadCallback> get downloadCallbacks;

  Stream<UploadCallback> get uploadCallbacks;

  /// Queues a download.
  ///
  /// [path]: The absolute path of the file on the device to be downloaded.
  /// Returns a [Stream] that provides updates to the download state.
  ///
  /// Restrictions:
  /// Only one download can be ongoing at a time. If not, [PlatformException] is thrown.
  ///
  /// Throws:
  /// [PlatformException] when there are unexpected failures on the native side.
  Future<void> download(String path);

  /// Queues an upload.
  ///
  /// [path]: The absolute path on the device where the file will be written.
  /// [data]: The file data to upload.
  /// Returns a [Stream] that provides updates to the upload state via [uploadCallbacks].
  ///
  /// Restrictions:
  /// Only one transfer can be ongoing at a time. If not, [PlatformException] is thrown.
  ///
  /// Throws:
  /// [PlatformException] when there are unexpected failures on the native side.
  Future<void> upload(String path, Uint8List data);

  /// Pauses any ongoing transfer. If no transfer is ongoing, it silently returns.
  Future<void> pauseTransfer();

  /// Continues any ongoing transfer. If no transfer is paused or queued, it silently returns.
  Future<void> continueTransfer();

  /// Cancels any ongoing transfer. If no transfer is ongoing, it silently returns.
  Future<void> cancelTransfer();

  /// Retrieves the status of an existing file from specified [path] of a target device.
  Future<int> status(String path);

  /// Clears any the native resources being held.
  Future<void> kill();
}

/// Implementation of the [FsManager] interface using Pigeon as the bridge to the native libraries.
class _FsManagerImpl implements FsManager {
  @override
  String remoteId;
  final FsManagerApi _api = FsManagerApi();

  _FsManagerImpl._internal(this.remoteId);

  @override
  Stream<DownloadCallback> get downloadCallbacks => getFileDownloadEvents()
      .where((event) {
        switch (event) {
          case OnDownloadProgressChangedEvent():
            return event.remoteId == this.remoteId;
          case OnDownloadFailedEvent():
            return event.remoteId == this.remoteId;
          case OnDownloadCancelledEvent():
            return event.remoteId == this.remoteId;
          case OnDownloadCompletedEvent():
            return event.remoteId == this.remoteId;
        }
      })
      .map(_translateDownload);

  @override
  Stream<UploadCallback> get uploadCallbacks => getFileUploadEvents()
      .where((event) {
        switch (event) {
          case OnUploadProgressChangedEvent():
            return event.remoteId == this.remoteId;
          case OnUploadFailedEvent():
            return event.remoteId == this.remoteId;
          case OnUploadCancelledEvent():
            return event.remoteId == this.remoteId;
          case OnUploadCompletedEvent():
            return event.remoteId == this.remoteId;
        }
      })
      .map(_translateUpload);

  @override
  Future<void> download(String path) {
    return _api.download(remoteId, path);
  }

  @override
  Future<void> upload(String path, Uint8List data) {
    return _api.upload(remoteId, path, data);
  }

  @override
  Future<void> cancelTransfer() {
    return _api.cancelTransfer(remoteId);
  }

  @override
  Future<void> continueTransfer() {
    return _api.continueTransfer(remoteId);
  }

  @override
  Future<void> pauseTransfer() {
    return _api.pauseTransfer(remoteId);
  }

  @override
  Future<int> status(String path) {
    return _api.status(remoteId, path);
  }

  @override
  Future<void> kill() {
    return _api.kill(remoteId);
  }

  static DownloadCallback _translateDownload(DownloadCallbackEvent event) => switch(event) {
    OnDownloadProgressChangedEvent() => OnDownloadProgressChanged(event.path, event.current, event.total, event.timestamp),
    OnDownloadFailedEvent() => OnDownloadFailed(event.path, event.cause),
    OnDownloadCancelledEvent() => OnDownloadCancelled(event.path),
    OnDownloadCompletedEvent() => OnDownloadCompleted(event.path, event.bytes),
  };

  static UploadCallback _translateUpload(UploadCallbackEvent event) => switch(event) {
    OnUploadProgressChangedEvent() => OnUploadProgressChanged(event.path, event.current, event.total, event.timestamp),
    OnUploadFailedEvent() => OnUploadFailed(event.path, event.cause),
    OnUploadCancelledEvent() => OnUploadCancelled(event.path),
    OnUploadCompletedEvent() => OnUploadCompleted(event.path),
  };
}

