//
// Copyright 2022 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

#if DEBUG

import MatrixSDKCrypto

typealias GetRoomAction = (String) -> MXRoom?

/// Wrapper around Rust-based `OlmMachine`, providing a more convenient API.
///
/// Two main responsibilities of the `MXCryptoMachine` are:
/// - mapping to and from raw strings passed into the Rust machine
/// - performing network requests and marking them as completed on behalf of the Rust machine
class MXCryptoMachine {
    actor RoomQueues {
        private var queues = [String: MXTaskQueue]()
        
        func getQueue(for roomId: String) -> MXTaskQueue {
            let queue = queues[roomId] ?? MXTaskQueue()
            queues[roomId] = queue
            return queue
        }
    }
    
    private static let storeFolder = "MXCryptoStore"
    
    enum Error: Swift.Error {
        case invalidStorage
        case invalidEvent
        case cannotSerialize
        case missingRoom
        case missingVerificationContent
        case missingVerificationRequest
        case missingVerification
        case missingEmojis
        case missingDecimals
        case cannotCancelVerification
    }
    
    private let machine: OlmMachine
    private let requests: MXCryptoRequests
    private let getRoomAction: GetRoomAction
    
    private let sessionsQueue = MXTaskQueue()
    private let syncQueue = MXTaskQueue()
    private var roomQueues = RoomQueues()
    
    private var hasUploadedInitialKeys = false
    private var initialKeysUploadCallback: (() -> Void)?
    
    private let log = MXNamedLog(name: "MXCryptoMachine")

    init(userId: String, deviceId: String, restClient: MXRestClient, getRoomAction: @escaping GetRoomAction) throws {
        let url = try Self.storeURL(for: userId)
        machine = try OlmMachine(
            userId: userId,
            deviceId: deviceId,
            path: url.path,
            passphrase: nil
        )
        requests = MXCryptoRequests(restClient: restClient)
        self.getRoomAction = getRoomAction
        
        setLogger(logger: self)
    }
    
    func onInitialKeysUpload(callback: @escaping () -> Void) {
        log.debug("->")
        
        if hasUploadedInitialKeys {
            callback()
        } else {
            initialKeysUploadCallback = callback
        }
    }
    
    private static func storeURL(for userId: String) throws -> URL {
        let container: URL
        if let sharedContainerURL = FileManager.default.applicationGroupContainerURL() {
            container = sharedContainerURL
        } else if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            container = url
        } else {
            throw Error.invalidStorage
        }

        return container
            .appendingPathComponent(Self.storeFolder)
            .appendingPathComponent(userId)
    }
    
    func deleteAllData() throws {
        let url = try Self.storeURL(for: machine.userId())
        try FileManager.default.removeItem(at: url)
    }
}

extension MXCryptoMachine: MXCryptoIdentity {
    var userId: String {
        return machine.userId()
    }
    
    var deviceId: String {
        return machine.deviceId()
    }
    
    var deviceCurve25519Key: String? {
        guard let key = machine.identityKeys()[kMXKeyCurve25519Type] else {
            log.error("Cannot get device curve25519 key")
            return nil
        }
        return key
    }
    
    var deviceEd25519Key: String? {
        guard let key = machine.identityKeys()[kMXKeyEd25519Type] else {
            log.error("Cannot get device ed25519 key")
            return nil
        }
        return key
    }
}

extension MXCryptoMachine: MXCryptoSyncing {
    func handleSyncResponse(
        toDevice: MXToDeviceSyncResponse?,
        deviceLists: MXDeviceListResponse?,
        deviceOneTimeKeysCounts: [String: NSNumber],
        unusedFallbackKeys: [String]?
    ) throws -> MXToDeviceSyncResponse {
        log.debug("Recieving sync changes")
        
        let events = toDevice?.jsonString() ?? "[]"
        let deviceChanges = DeviceLists(
            changed: deviceLists?.changed ?? [],
            left: deviceLists?.left ?? []
        )
        let keyCounts = deviceOneTimeKeysCounts.compactMapValues { $0.int32Value }
        
        let result = try machine.receiveSyncChanges(
            events: events,
            deviceChanges: deviceChanges,
            keyCounts: keyCounts,
            unusedFallbackKeys: unusedFallbackKeys
        )
        
        guard let json = MXTools.deserialiseJSONString(result) as? [AnyHashable: Any] else {
            log.error("Result cannot be serialized", context: [
                "result": result
            ])
            return MXToDeviceSyncResponse()
        }
        return MXToDeviceSyncResponse(fromJSON: json)
    }
    
    func completeSync() async throws {
        try await syncQueue.sync { [weak self] in
            try await self?.processOutgoingRequests()
        }
    }
    
    // MARK: - Private
    
    private func handleRequest(_ request: Request) async throws {
        switch request {
        case .toDevice(let requestId, let eventType, let body):
            try await requests.sendToDevice(
                request: .init(eventType: eventType, body: body)
            )
            try markRequestAsSent(requestId: requestId, requestType: .toDevice)

        case .keysUpload(let requestId, let body):
            let response = try await requests.uploadKeys(
                request: .init(body: body, deviceId: machine.deviceId())
            )
            try markRequestAsSent(requestId: requestId, requestType: .keysUpload, response: response.jsonString())
            broadcastInitialKeysUploadIfNecessary()
            
        case .keysQuery(let requestId, let users):
            let response = try await requests.queryKeys(users: users)
            try markRequestAsSent(requestId: requestId, requestType: .keysQuery, response: response.jsonString())
            
        case .keysClaim(let requestId, let oneTimeKeys):
            let response = try await requests.claimKeys(
                request: .init(oneTimeKeys: oneTimeKeys)
            )
            try markRequestAsSent(requestId: requestId, requestType: .keysClaim, response: response.jsonString())

        case .keysBackup(let requestId, let version, let rooms):
            let response = try await requests.backupKeys(
                request: .init(version: version, rooms: rooms)
            )
            try markRequestAsSent(requestId: requestId, requestType: .keysBackup, response: MXTools.serialiseJSONObject(response))
            
        case .roomMessage(let requestId, let roomId, let eventType, let content):
            guard let eventID = try await sendRoomMessage(roomId: roomId, eventType: eventType, content: content) else {
                throw Error.invalidEvent
            }
            let event = [
                "event_id": eventID
            ]
            try markRequestAsSent(requestId: requestId, requestType: .roomMessage, response: MXTools.serialiseJSONObject(event))
            
        case .signatureUpload(let requestId, let body):
            try await requests.uploadSignatures(
                request: .init(body: body)
            )
            let event = [
                "failures": [:]
            ]
            try markRequestAsSent(requestId: requestId, requestType: .signatureUpload, response: MXTools.serialiseJSONObject(event))
        }
    }
    
    private func markRequestAsSent(requestId: String, requestType: RequestType, response: String? = nil) throws {
        try self.machine.markRequestAsSent(requestId: requestId, requestType: requestType, response: response ?? "")
    }
    
    private func processOutgoingRequests() async throws {
        let requests = try machine.outgoingRequests()
        
        try await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self = self else { return }
            for request in requests {
                group.addTask {
                    try await self.handleRequest(request)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    private func sendRoomMessage(roomId: String, eventType: String, content: String) async throws -> String? {
        guard let room = getRoomAction(roomId) else {
            throw Error.missingRoom
        }
        return try await requests.roomMessage(
            request: .init(
                room: room,
                eventType: eventType,
                content: content
            )
        )
    }
    
    private func broadcastInitialKeysUploadIfNecessary() {
        guard !hasUploadedInitialKeys else {
            return
        }
        hasUploadedInitialKeys = true
        initialKeysUploadCallback?()
        initialKeysUploadCallback = nil
    }
}

extension MXCryptoMachine: MXCryptoDevicesSource {
    func devices(userId: String) -> [Device] {
        do {
            return try machine.getUserDevices(userId: userId, timeout: 0)
        } catch {
            log.error("Cannot fetch devices", context: error)
            return []
        }
    }
    
    func device(userId: String, deviceId: String) -> Device? {
        do {
            return try machine.getDevice(userId: userId, deviceId: deviceId, timeout: 0)
        } catch {
            log.error("Cannot fetch device", context: error)
            return nil
        }
    }
}

extension MXCryptoMachine: MXCryptoUserIdentitySource {
    func isUserVerified(userId: String) -> Bool {
        do {
            return try machine.isIdentityVerified(userId: userId)
        } catch {
            log.error("Failed checking user verification status", context: error)
            return false
        }
    }
    
    func userIdentity(userId: String) -> UserIdentity? {
        do {
            return try machine.getIdentity(userId: userId, timeout: 0)
        } catch {
            log.error("Failed fetching user identity")
            return nil
        }
    }
    
    func downloadKeys(users: [String]) async throws {
        try await handleRequest(
            .keysQuery(requestId: UUID().uuidString, users: users)
        )
    }
    
    func manuallyVerifyUser(userId: String) async throws {
        let request = try machine.verifyIdentity(userId: userId)
        try await requests.uploadSignatures(request: request)
    }
    
    func manuallyVerifyDevice(userId: String, deviceId: String) async throws {
        let request = try machine.verifyDevice(userId: userId, deviceId: deviceId)
        try await requests.uploadSignatures(request: request)
    }
}

extension MXCryptoMachine: MXCryptoRoomEventEncrypting {
    func shareRoomKeysIfNecessary(roomId: String, users: [String]) async throws {
        try await sessionsQueue.sync { [weak self] in
            try await self?.updateTrackedUsers(users: users)
            try await self?.getMissingSessions(users: users)
        }
        
        let roomQueue = await roomQueues.getQueue(for: roomId)
        try await roomQueue.sync { [weak self] in
            try await self?.shareRoomKey(roomId: roomId, users: users)
        }
    }
    
    func encryptRoomEvent(
        content: [AnyHashable : Any],
        roomId: String,
        eventType: String,
        users: [String]
    ) async throws -> [String : Any] {
        guard let content = MXTools.serialiseJSONObject(content) else {
            throw Error.cannotSerialize
        }
        
        try await shareRoomKeysIfNecessary(roomId: roomId, users: users)
        let event = try machine.encrypt(roomId: roomId, eventType: eventType as String, content: content)
        return MXTools.deserialiseJSONString(event) as? [String: Any] ?? [:]
    }
    
    func decryptRoomEvent(_ event: MXEvent) -> MXEventDecryptionResult {
        guard let roomId = event.roomId, let eventString = event.jsonString() else {
            log.failure("Invalid event")
            
            let result = MXEventDecryptionResult()
            result.error = Error.invalidEvent
            return result
        }
        
        do {
            let decryptedEvent = try machine.decryptRoomEvent(event: eventString, roomId: roomId)
            let result = try MXEventDecryptionResult(event: decryptedEvent)
            log.debug("Successfully decrypted event `\(result.clearEvent["type"] ?? "unknown")`")
            return result
            
        // `Megolm` error does not currently expose the type of "missing keys" error, so have to match against
        // hardcoded non-localized error message. Will be changed in future PR
        } catch DecryptionError.Megolm(message: "decryption failed because the room key is missing") {
            let result = MXEventDecryptionResult()
            result.error = NSError(
                domain: MXDecryptingErrorDomain,
                code: Int(MXDecryptingErrorUnknownInboundSessionIdCode.rawValue),
                userInfo: [
                    NSLocalizedDescriptionKey: MXDecryptingErrorUnknownInboundSessionIdReason
                ]
            )
            log.error("Failed decrypting due to missing key")
            return result
        } catch {
            let result = MXEventDecryptionResult()
            result.error = error
            log.error("Failed decrypting", context: error)
            return result
        }
    }
    
    func requestRoomKey(event: MXEvent) async throws {
        guard let roomId = event.roomId, let eventString = event.jsonString() else {
            throw Error.invalidEvent
        }
        
        log.debug("->")
        let result = try machine.requestRoomKey(event: eventString, roomId: roomId)
        if let cancellation = result.cancellation {
            try await handleRequest(cancellation)
        }
        try await handleRequest(result.keyRequest)
                
    }
    
    func discardRoomKey(roomId: String) {
        do {
            try machine.discardRoomKey(roomId: roomId)
        } catch {
            log.error("Cannot discard room key", context: error)
        }
    }
    
    // MARK: - Private
    
    private func updateTrackedUsers(users: [String]) async throws {
        machine.updateTrackedUsers(users: users)
        try await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self = self else { return }
            
            for request in try machine.outgoingRequests() {
                guard case .keysQuery = request else {
                    continue
                }
                
                group.addTask {
                    try await self.handleRequest(request)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    private func getMissingSessions(users: [String]) async throws {
        guard
            let request = try machine.getMissingSessions(users: users),
            case .keysClaim = request
        else {
            return
        }
        try await handleRequest(request)
    }
    
    private func shareRoomKey(roomId: String, users: [String]) async throws {
        let requests = try machine.shareRoomKey(roomId: roomId, users: users)
        try await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self = self else { return }
            
            for request in requests {
                guard case .toDevice = request else {
                    continue
                }
                
                group.addTask {
                    try await self.handleRequest(request)
                }
            }
            
            try await group.waitForAll()
        }
    }
}

extension MXCryptoMachine: MXCryptoCrossSigning {
    func crossSigningStatus() -> CrossSigningStatus {
        return machine.crossSigningStatus()
    }
    
    func bootstrapCrossSigning(authParams: [AnyHashable: Any]) async throws {
        let result = try machine.bootstrapCrossSigning()
        let _ = try await [
            requests.uploadSigningKeys(request: result.uploadSigningKeysRequest, authParams: authParams),
            requests.uploadSignatures(request: result.signatureRequest)
        ]
    }
    
    func exportCrossSigningKeys() -> CrossSigningKeyExport? {
        machine.exportCrossSigningKeys()
    }
}

extension MXCryptoMachine: MXCryptoVerificationRequesting {
    func receiveUnencryptedVerificationEvent(event: MXEvent, roomId: String) {
        guard let string = event.jsonString() else {
            log.failure("Invalid event")
            return
        }
        do {
            try machine.receiveUnencryptedVerificationEvent(event: string, roomId: roomId)
        } catch {
            log.error("Error receiving unencrypted event", context: error)
        }
    }
    
    func requestSelfVerification(methods: [String]) async throws -> VerificationRequest {
        guard let result = try machine.requestSelfVerification(methods: methods) else {
            throw Error.missingVerification
        }
        try await handleOutgoingVerificationRequest(result.request)
        return result.verification
    }
    
    func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> VerificationRequest {
        guard let content = try machine.verificationRequestContent(userId: userId, methods: methods) else {
            throw Error.missingVerificationContent
        }
        
        let eventId = try await sendRoomMessage(
            roomId: roomId,
            eventType: kMXEventTypeStringRoomMessage,
            content: content
        )
        guard let eventId = eventId else {
            throw Error.invalidEvent
        }
        
        let request = try machine.requestVerification(
            userId: userId,
            roomId: roomId,
            eventId: eventId,
            methods: methods
        )
        
        guard let request = request else {
            throw Error.missingVerificationRequest
        }
        return request
    }
    
    func verificationRequests(userId: String) -> [VerificationRequest] {
        return machine.getVerificationRequests(userId: userId)
    }
    
    func verificationRequest(userId: String, flowId: String) -> VerificationRequest? {
        return machine.getVerificationRequest(userId: userId, flowId: flowId)
    }
    
    func acceptVerificationRequest(userId: String, flowId: String, methods: [String]) async throws {
        guard let request = machine.acceptVerificationRequest(userId: userId, flowId: flowId, methods: methods) else {
            throw Error.missingVerificationRequest
        }
        try await handleOutgoingVerificationRequest(request)
    }
    
    func cancelVerification(userId: String, flowId: String, cancelCode: String) async throws {
        guard let request = machine.cancelVerification(userId: userId, flowId: flowId, cancelCode: cancelCode) else {
            throw Error.cannotCancelVerification
        }
        try await handleOutgoingVerificationRequest(request)
    }
    
    // MARK: - Private
    
    private func handleOutgoingVerificationRequest(_ request: OutgoingVerificationRequest) async throws {
        switch request {
        case .toDevice(_, let eventType, let body):
            try await requests.sendToDevice(
                request: .init(
                    eventType: eventType,
                    body: body
                )
            )
        case .inRoom(_, let roomId, let eventType, let content):
            let _ = try await sendRoomMessage(
                roomId: roomId,
                eventType: eventType,
                content: content
            )
        }
    }
}

extension MXCryptoMachine: MXCryptoVerifying {
    func verification(userId: String, flowId: String) -> Verification? {
        return machine.getVerification(userId: userId, flowId: flowId)
    }
    
    func confirmVerification(userId: String, flowId: String) async throws {
        let result = try machine.confirmVerification(userId: userId, flowId: flowId)
        guard let result = result else {
            throw Error.missingVerification
        }
        
        if let request = result.signatureRequest {
            try await requests.uploadSignatures(request: request)
        }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for request in result.requests {
                group.addTask {
                    try await self.handleOutgoingVerificationRequest(request)
                }
            }
            
            try await group.waitForAll()
        }
    }
}

extension MXCryptoMachine: MXCryptoSASVerifying {
    func startSasVerification(userId: String, flowId: String) async throws -> Sas {
        guard let result = try machine.startSasVerification(userId: userId, flowId: flowId) else {
            throw Error.missingVerification
        }
        try await handleOutgoingVerificationRequest(result.request)
        return result.sas
    }
    
    func startSasVerification(userId: String, deviceId: String) async throws -> Sas {
        guard let result = try machine.startSasWithDevice(userId: userId, deviceId: deviceId) else {
            throw Error.missingVerification
        }
        try await handleOutgoingVerificationRequest(result.request)
        return result.sas
    }
    
    func acceptSasVerification(userId: String, flowId: String) async throws {
        guard let request = machine.acceptSasVerification(userId: userId, flowId: flowId) else {
            throw Error.missingVerification
        }
        try await handleOutgoingVerificationRequest(request)
    }

    func emojiIndexes(sas: Sas) throws -> [Int] {
        guard let indexes = machine.getEmojiIndex(userId: sas.otherUserId, flowId: sas.flowId) else {
            throw Error.missingEmojis
        }
        return indexes.map(Int.init)
    }
    
    func sasDecimals(sas: Sas) throws -> [Int] {
        guard let decimals = machine.getDecimals(userId: sas.otherUserId, flowId: sas.flowId) else {
            throw Error.missingDecimals
        }
        return decimals.map(Int.init)
    }
}

extension MXCryptoMachine: MXCryptoQRCodeVerifying {
    func startQrVerification(userId: String, flowId: String) throws -> QrCode {
        guard let result = try machine.startQrVerification(userId: userId, flowId: flowId) else {
            throw Error.missingVerification
        }
        return result
    }
    
    func scanQrCode(userId: String, flowId: String, data: Data) async throws -> QrCode {
        let string = MXBase64Tools.base64(from: data)
        guard let result = machine.scanQrCode(userId: userId, flowId: flowId, data: string) else {
            throw Error.missingVerification
        }
        try await handleOutgoingVerificationRequest(result.request)
        return result.qr
    }
    
    func generateQrCode(userId: String, flowId: String) throws -> Data {
        guard let string = machine.generateQrCode(userId: userId, flowId: flowId) else {
            throw Error.missingVerification
        }
        return MXBase64Tools.data(fromBase64: string)
    }
}

extension MXCryptoMachine: MXCryptoBackup {
    var isBackupEnabled: Bool {
        return machine.backupEnabled()
    }
    
    var backupKeys: BackupKeys? {
        do {
            return try machine.getBackupKeys()
        } catch {
            log.error("Failed fetching backup keys", context: error)
            return nil
        }
    }
    
    var roomKeyCounts: RoomKeyCounts? {
        do {
            return try machine.roomKeyCounts()
        } catch {
            log.error("Cannot get room key counts", context: error)
            return nil
        }
    }
    
    func enableBackup(key: MegolmV1BackupKey, version: String) throws {
        try machine.enableBackupV1(key: key, version: version)
    }
    
    func disableBackup() {
        do {
            try machine.disableBackup()
        } catch {
            log.error("Failed disabling backup", context: error)
        }
    }
    
    func saveRecoveryKey(key: BackupRecoveryKey, version: String?) throws {
        try machine.saveRecoveryKey(key: key, version: version)
    }
    
    func verifyBackup(version: MXKeyBackupVersion) -> Bool {
        guard let string = version.jsonString() else {
            log.error("Cannot serialize backup version")
            return false
        }
        
        do {
            return try machine.verifyBackup(authData: string)
        } catch {
            log.error("Failed verifying backup", context: error)
            return false
        }
    }
    
    func sign(object: [AnyHashable: Any]) throws -> [String: [String: String]] {
        guard let message = MXCryptoTools.canonicalJSONString(forJSON: object) else {
            throw Error.cannotSerialize
        }
        return machine.sign(message: message)
    }
    
    func backupRoomKeys() async throws {
        guard
            let request = try machine.backupRoomKeys(),
            case .keysBackup = request
        else {
            return
        }
        try await handleRequest(request)
    }
    
    func importDecryptedKeys(roomKeys: [MXMegolmSessionData], progressListener: ProgressListener) throws -> KeysImportResult {
        let jsonKeys = roomKeys.compactMap { $0.jsonDictionary() }
        guard let json = MXTools.serialiseJSONObject(jsonKeys) else {
            throw Error.cannotSerialize
        }
        return try machine.importDecryptedRoomKeys(keys: json, progressListener: progressListener)
    }
}

extension MXCryptoMachine: Logger {
    func log(logLine: String) {
        MXLog.debug("[MXCryptoMachine] \(logLine)")
    }
    
    func log(error: String) {
        MXLog.error("[MXCryptoMachine] Error", context: [
            "error": error
        ])
    }
}

#endif
