// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

public struct ProcessResult {
    public let exitCode: Int32
    public let stdoutData: Data
    public let stderrData: Data

    public var stdoutString: String {
        String(data: stdoutData, encoding: .utf8) ?? ""
    }

    public var stderrString: String {
        String(data: stderrData, encoding: .utf8) ?? ""
    }

    public var isSuccess: Bool { exitCode == 0 }
}

public enum ProcessRunner {
    /// Runs a process synchronously with arguments and environment.
    public static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 60.0
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let env = environment {
            var fullEnv = ProcessInfo.processInfo.environment
            for (k, v) in env {
                fullEnv[k] = v
            }
            process.environment = fullEnv
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(
                exitCode: -1,
                stdoutData: Data(),
                stderrData: Data(error.localizedDescription.utf8)
            )
        }

        let dispatchGroup = DispatchGroup()
        var outData = Data()
        var errData = Data()

        dispatchGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            dispatchGroup.leave()
        }

        dispatchGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            dispatchGroup.leave()
        }

        let waitResult = dispatchGroup.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            let killDeadline = Date().addingTimeInterval(1.0)
            while process.isRunning && Date() < killDeadline {
                usleep(20_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            return ProcessResult(
                exitCode: -2,
                stdoutData: outData,
                stderrData: Data("Process execution timed out".utf8)
            )
        }

        process.waitUntilExit()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdoutData: outData,
            stderrData: errData
        )
    }
}
