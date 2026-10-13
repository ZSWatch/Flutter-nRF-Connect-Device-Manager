# Nordic iOS McuManager 1.10.1

This directory retains the Apache-2.0-licensed CocoaPods source distribution
of Nordic's tag 1.10.1 from
https://github.com/NordicSemiconductor/IOS-nRF-Connect-Device-Manager.
The original source hashes are in UPSTREAM_FILES.json and the license is retained.
SwiftCBOR 0.4.7 and ZIPFoundation 0.9.19 dependencies remain unchanged.

Local fixes preserve SDK protocol/DFU/file implementations:
- The already-connected discovery path filters by the service UUID; a new
  central waits for poweredOn before retrieving a peripheral.
- invalidate() permanently fences an app-owned session and cancels queued work;
  reconnectable close() keeps its existing DFU semantics.
- The reorder buffer serializes admission, cancellation and readiness. It
  respects canSendWriteWithoutResponse instead of forcing writes after 15 ms.

The companion owns one SDK operation at a time and calls invalidate() on Stop,
Forget or session loss. Pending mutating-operation outcomes remain uncertain
when a packet was handed to CoreBluetooth before cancellation.

- McuMgrExecResponse exposes Zephyr shell `ret` as a signed returnCode, distinct
  from transport/protocol `rc`. Nonzero command exits remain visible to callers.

Plugin registration is lazy: opening a Flutter engine registers channels without
constructing a Bluetooth manager or prompting for Bluetooth authorization.

The optional retryOnMissingResponse setting preserves the upstream default but
lets the companion forbid replay after a fully admitted request loses its
response. Reset and arbitrary shell commands therefore retain unknown outcomes
instead of being executed again by the SDK transport.

MCUboot parsing now checks header/table/entry bounds before reading selected
files. Its existing parser and error types are retained. TLV tables end at their
specified total length, and generic integer reads copy bytes into aligned
storage. Host tests compile the actual SDK parser/read method and reject short
or malformed input without a process trap. Image authenticity remains the
watch bootloader's responsibility.

FirmwareUpgradeManager.abort(with:) is a terminal app-owner teardown API, kept
separate from upload-only cancel(). After the owner invalidates the transport,
it removes the reset observer, stops upload controllers, fences later state/
command transitions and releases the SDK's self-retention cycle even when the
transport never delivers a cancelled callback. Normal DFU close/reconnect and
user cancellation semantics remain the existing SDK paths.
