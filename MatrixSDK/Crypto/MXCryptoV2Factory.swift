// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

@objc public class MXCryptoV2Factory: NSObject {
    enum Error: Swift.Error {
        case cryptoNotAvailable
    }
    
    @objc public static let shared = MXCryptoV2Factory()
    private let log = MXNamedLog(name: "MXCryptoV2Factory")
    
    private var lastDeprecatedVersion: MXCryptoVersion {
        .deprecated2
    }
    
    @objc public func buildCrypto(
        session: MXSession!,
        migrationProgress: ((Double) -> Void)?,
        success: @escaping (MXCrypto?) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        guard
            let session = session,
            let restClient = session.matrixRestClient,
            let credentials = session.credentials,
            let userId = credentials.userId,
            let deviceId = credentials.deviceId
        else {
            log.failure("Missing required dependencies")
            failure(Error.cryptoNotAvailable)
            return
        }
        
        log.debug("Building crypto module")
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.deprecateLegacyStoreIfNecessary(credentials: credentials) {
                    migrationProgress?($0)
                }
            } catch {
                self.log.error("Failed to migrate / deprecate legacy store", context: error)
            }
            
            do {
                let crypto = try await MXCryptoV2(
                    userId: userId,
                    deviceId: deviceId,
                    session: session,
                    restClient: restClient
                )
                await MainActor.run {
                    success(crypto)
                }
            } catch {
                self.log.failure("Cannot create crypto", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    private func deprecateLegacyStoreIfNecessary(
        credentials: MXCredentials,
        updateProgress: @escaping ((Double) -> Void)
    ) throws {
        guard
            MXRealmCryptoStore.hasData(for: credentials),
            let legacyStore = MXRealmCryptoStore(credentials: credentials)
        else {
            log.debug("Legacy crypto store does not exist")
            return
        }
        
        log.debug("Legacy crypto store exists")
        try migrateIfNecessary(legacyStore: legacyStore, updateProgress: updateProgress)
        
        log.debug("Deleting legacy store after successfull migration")
        MXRealmCryptoStore.delete(with: credentials)
    }
    
    private func migrateIfNecessary(
        legacyStore: MXCryptoStore,
        updateProgress: @escaping (Double) -> Void
    ) throws {
        let legacyVersion = legacyStore.cryptoVersion.rawValue
        guard legacyVersion < lastDeprecatedVersion.rawValue else {
            log.debug("Legacy crypto has already been deprecated, no need to migrate")
            return
        }

        log.debug("Requires migration from legacy crypto version \(legacyVersion) to version \(lastDeprecatedVersion.rawValue)")
        let migration = MXCryptoMigrationV2(legacyStore: legacyStore)
        
        if legacyVersion < MXCryptoVersion.deprecated1.rawValue {
            log.debug("Full migration of crypto data")
            try migration.migrateAllData(updateProgress: updateProgress)
            
        } else if legacyVersion < MXCryptoVersion.deprecated2.rawValue {
            log.debug("Partial migration of room and global settings")
            try migration.migrateRoomAndGlobalSettingsOnly(updateProgress: updateProgress)
            
        } else {
            log.failure("Unhandled crypto version", context: legacyStore.cryptoVersion.rawValue)
        }
    }
}
