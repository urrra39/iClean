import Darwin
import Foundation

/// Local IPC between the daemon and the CLI/menu app: one JSON request line and one
/// JSON response per connection over a Unix domain socket in iClean's private
/// directory. No network listener exists anywhere in iClean.
public struct Request: Codable, Sendable {
    public var cmd: String
    public var app: String?
    public var value: String?
    public var json: Bool?

    public init(_ cmd: String, app: String? = nil, value: String? = nil, json: Bool? = nil) {
        self.cmd = cmd
        self.app = app
        self.value = value
        self.json = json
    }
}

public struct Response: Codable, Sendable {
    public var ok: Bool
    public var text: String
    /// Machine-readable payload (JSON text) when the request asked for it.
    public var data: String?

    public init(ok: Bool, text: String, data: String? = nil) {
        self.ok = ok
        self.text = text
        self.data = data
    }
}

public final class IPCServer {
    private let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let handler: (Request) -> Response

    /// `handler` runs on the main queue.
    public init(path: String, handler: @escaping (Request) -> Response) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            path.utf8CString.withUnsafeBytes { buf.copyMemory(from: $0) }
        }
        let old = umask(0o077)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(old)
        guard rc == 0, listen(fd, 16) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        src.setEventHandler { [weak self] in self?.accept() }
        src.resume()
        source = src
    }

    public func stop() {
        source?.cancel()
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private func accept() {
        let c = Darwin.accept(fd, nil, nil)
        guard c >= 0 else { return }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(c, &uid, &gid) == 0, uid == getuid() else { close(c); return }
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var nosig: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
        DispatchQueue.global().async {
            defer { close(c) }
            guard let line = IPC.readLine(c, limit: 64 << 10),
                  let req = try? JSONDecoder().decode(Request.self, from: line) else {
                IPC.write(c, Response(ok: false, text: "bad request"))
                return
            }
            let resp = DispatchQueue.main.sync { self.handler(req) }
            IPC.write(c, resp)
        }
    }
}

public enum IPC {
    static func readLine(_ fd: Int32, limit: Int) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while data.count < limit {
            let n = read(fd, &byte, 1)
            if n <= 0 { return data.isEmpty ? nil : data }
            if byte == 0x0A { return data }
            data.append(byte)
        }
        return nil
    }

    static func write(_ fd: Int32, _ r: Response) {
        guard var d = try? JSONEncoder().encode(r) else { return }
        d.append(0x0A)
        d.withUnsafeBytes { buf in
            var off = 0
            while off < buf.count {
                let n = Darwin.write(fd, buf.baseAddress! + off, buf.count - off)
                if n <= 0 { return }
                off += n
            }
        }
    }

    /// Sends one request. Returns nil when the daemon is not running.
    public static func send(_ req: Request, path: String, timeout: Int = 10) -> Response? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            path.utf8CString.withUnsafeBytes { buf.copyMemory(from: $0) }
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { return nil }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var nosig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
        guard var d = try? JSONEncoder().encode(req) else { return nil }
        d.append(0x0A)
        let sent = d.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard sent == d.count, let line = readLine(fd, limit: 32 << 20) else { return nil }
        return try? JSONDecoder().decode(Response.self, from: line)
    }
}
