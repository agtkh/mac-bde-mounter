// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import os.log

private let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "helper-main")

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("Incoming XPC connection from pid: \(newConnection.processIdentifier)")

        let interface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = HelperService()

        newConnection.invalidationHandler = {
            logger.info("XPC connection invalidated (pid: \(newConnection.processIdentifier))")
        }
        newConnection.interruptionHandler = {
            logger.warning("XPC connection interrupted (pid: \(newConnection.processIdentifier))")
        }

        newConnection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: BLMConstants.machServiceName)
listener.delegate = delegate

if let req = BLMConstants.requirement(forKey: BLMConstants.clientRequirementKey) {
    if #available(macOS 14.0, *) {
        listener.setConnectionCodeSigningRequirement(req)
        logger.info("Enforced client code signing requirement: \(req, privacy: .public)")
    } else {
        logger.info("Configured client requirement for macOS: \(req, privacy: .public)")
    }
}

logger.info("Privileged helper starting: \(BLMConstants.machServiceName, privacy: .public)")
listener.resume()
RunLoop.main.run()
