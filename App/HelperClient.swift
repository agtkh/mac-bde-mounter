// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import os.log

public final class HelperClient {
    public static let shared = HelperClient()
    private let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "helper-client")

    private var connection: NSXPCConnection?
    private let lock = NSLock()

    private init() {}

    private func getOrCreateConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let conn = connection {
            return conn
        }

        let conn = NSXPCConnection(machServiceName: BLMConstants.machServiceName, options: .privileged)
        let interface = NSXPCInterface(with: HelperProtocol.self)
        conn.remoteObjectInterface = interface

        if let req = BLMConstants.requirement(forKey: BLMConstants.helperRequirementKey) {
            if #available(macOS 14.0, *) {
                conn.setCodeSigningRequirement(req)
                logger.info("Enforced helper code signing requirement: \(req, privacy: .public)")
            }
        }

        conn.invalidationHandler = { [weak self] in
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
            self?.logger.warning("Helper XPC connection was invalidated")
        }

        conn.interruptionHandler = { [weak self] in
            self?.logger.warning("Helper XPC connection was interrupted")
        }

        conn.resume()
        self.connection = conn
        return conn
    }

    private func getProxy(errorHandler: @escaping (Error) -> Void) -> HelperProtocol? {
        let conn = getOrCreateConnection()
        return conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logger.error("XPC remote object error: \(error.localizedDescription, privacy: .public)")
            errorHandler(error)
        } as? HelperProtocol
    }

    public func version(completion: @escaping (Result<String, Error>) -> Void) {
        guard let proxy = getProxy(errorHandler: { completion(.failure($0)) }) else {
            completion(.failure(BLMHelperError.make(.general, description: "Could not create XPC proxy")))
            return
        }
        proxy.version { ver in
            completion(.success(ver))
        }
    }

    public func probe(bsdName: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let proxy = getProxy(errorHandler: { completion(.failure($0)) }) else {
            completion(.failure(BLMHelperError.make(.general, description: "Could not create XPC proxy")))
            return
        }
        proxy.probe(bsdName: bsdName) { dict, error in
            if let error = error {
                completion(.failure(error))
            } else if let dict = dict as? [String: Any] {
                completion(.success(dict))
            } else {
                completion(.failure(BLMHelperError.make(.general, description: "Empty response from probe")))
            }
        }
    }

    public func checkFDA(completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let proxy = getProxy(errorHandler: { completion(.failure($0)) }) else {
            completion(.failure(BLMHelperError.make(.general, description: "Could not create XPC proxy")))
            return
        }
        proxy.checkFDA { allowed in
            completion(.success(allowed))
        }
    }

    public func ensureFuseT(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let proxy = getProxy(errorHandler: { completion(.failure($0)) }) else {
            completion(.failure(BLMHelperError.make(.general, description: "Could not create XPC proxy")))
            return
        }
        proxy.ensureFuseT { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    public func unlock(
        bsdName: String,
        volumeGUID: String,
        password: SecureBytes,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let proxy = getProxy(errorHandler: { completion(.failure($0)) }) else {
            completion(.failure(BLMHelperError.make(.general, description: "Could not create XPC proxy")))
            return
        }
        var data = password.makeData()
        proxy.unlock(bsdName: bsdName, volumeGUID: volumeGUID, password: data) { imageBSD, error in
            SecureBytes.wipe(&data)
            if let error = error {
                completion(.failure(error))
            } else if let bsd = imageBSD {
                completion(.success(bsd))
            } else {
                completion(.failure(BLMHelperError.make(.general, description: "No device returned from unlock")))
            }
        }
    }

    public func teardown(volumeGUID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let proxy = getProxy(errorHandler: { completion(.failure($0)) }) else {
            completion(.failure(BLMHelperError.make(.general, description: "Could not create XPC proxy")))
            return
        }
        proxy.teardown(volumeGUID: volumeGUID) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    public func activeSessions(completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        guard let proxy = getProxy(errorHandler: { completion(.failure($0)) }) else {
            completion(.failure(BLMHelperError.make(.general, description: "Could not create XPC proxy")))
            return
        }
        proxy.activeSessions { list in
            let res = list.compactMap { $0 as? [String: Any] }
            completion(.success(res))
        }
    }
}
