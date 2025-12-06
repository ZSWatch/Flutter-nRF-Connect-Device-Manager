package no.nordicsemi.android.mcumgr_flutter.utils

import no.nordicsemi.android.mcumgr_flutter.UploadCallbackEvent
import no.nordicsemi.android.mcumgr_flutter.GetFileUploadEventsStreamHandler
import no.nordicsemi.android.mcumgr_flutter.PigeonEventSink

class FsUploadStreamHandler : GetFileUploadEventsStreamHandler() {
    private var sink: PigeonEventSink<UploadCallbackEvent>? = null

    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<UploadCallbackEvent>
    ) {
        this.sink = sink;
    }

    override fun onCancel(p0: Any?) {
        this.sink = null;
    }

    fun onEvent(event: UploadCallbackEvent) {
        sink?.success(event);
    }
}

