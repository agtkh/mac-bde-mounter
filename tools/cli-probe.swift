// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

@main
struct CLIProbe {
    static func main() {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: cli-probe <bsdName> [bsdName2 ...]")
            print("Example: sudo ./cli-probe disk6s1 disk6s2")
            exit(1)
        }

        for bsdName in CommandLine.arguments.dropFirst() {
            print("========================================")
            print("Probing BSD Name: \(bsdName)")
            print("Device path:      /dev/r\(bsdName)")
            
            let rawPath = "/dev/r\(bsdName)"
            let fd = open(rawPath, O_RDONLY)
            if fd >= 0 {
                var rawPtr: UnsafeMutableRawPointer? = nil
                let alignRet = posix_memalign(&rawPtr, 4096, 4096)
                if alignRet == 0, let buffer = rawPtr {
                    let bytesRead = read(fd, buffer, 4096)
                    close(fd)
                    if bytesRead >= 512 {
                        let data = Data(bytes: buffer, count: bytesRead)
                        let sigAt3 = String(data: data.subdata(in: 3..<min(11, data.count)), encoding: .utf8) ?? "<invalid>"
                        let sigAt52 = (data.count >= 0x52 + 8) ? (String(data: data.subdata(in: 0x52..<0x52 + 8), encoding: .utf8) ?? "<invalid>") : "<too short>"
                        print("Signature at offset 3:    \(sigAt3.debugDescription)")
                        print("Signature at offset 0x52: \(sigAt52.debugDescription)")
                    }
                    free(buffer)
                }
            } else {
                let err = errno
                print("Note: Direct open failed with errno \(err) (\(String(cString: strerror(err))))")
                if err == EPERM || err == EACCES {
                    print("=> Permission denied. Please run with 'sudo'.")
                }
            }

            let result = DeviceProbe.probe(bsdName: bsdName)
            print("DeviceProbe Result:")
            print("  isBitLocker:     \(result.isBitLocker)")
            print("  isBitLockerToGo: \(result.isBitLockerToGo)")
            print("  volumeGUID:      \(result.volumeGUID ?? "None")")
            print("========================================")
        }
    }
}
