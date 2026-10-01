import Darwin
import Foundation
import ICCore

/// S4 raw facts: an app tree's open sockets and files, via libproc. Works without
/// root for same-user processes. The cost is bounded: at most `maxFDs` descriptors
/// per process, and the daemon only inspects apps that passed every cheaper check.
public enum Inspector {
    public static let maxFDs = 4096

    public static func fds(_ pid: Int32) -> [proc_fdinfo] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let n = min(Int(size) / MemoryLayout<proc_fdinfo>.size, maxFDs)
        var buf = [proc_fdinfo](repeating: proc_fdinfo(), count: n)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &buf, Int32(n * MemoryLayout<proc_fdinfo>.size))
        return Array(buf.prefix(max(0, Int(got)) / MemoryLayout<proc_fdinfo>.size))
    }

    public static func sockets(_ pid: Int32) -> [SocketFact] {
        var out: [SocketFact] = []
        for fd in fds(pid) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var si = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, size) == size else { continue }
            let s = si.psi
            let queued = Int(s.soi_rcv.sbi_cc) + Int(s.soi_snd.sbi_cc)
            switch Int32(s.soi_kind) {
            case Int32(SOCKINFO_TCP):
                let tcp = s.soi_proto.pri_tcp
                let ini = tcp.tcpsi_ini
                let lport = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport)))
                let fport = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_fport)))
                let state = tcp.tcpsi_state
                out.append(
                    SocketFact(
                        kind: .tcp, listening: state == TSI_S_LISTEN, established: state == TSI_S_ESTABLISHED,
                        localPort: lport, remotePort: fport, remoteIsLoopback: isLoopback(ini),
                        queuedBytes: queued, key: "\(pid):\(fd.proc_fd):\(lport)-\(fport)"))
            case Int32(SOCKINFO_IN):
                out.append(SocketFact(kind: .udp, queuedBytes: queued, key: "\(pid):udp\(fd.proc_fd)"))
            default:
                continue
            }
        }
        return out
    }

    static func isLoopback(_ ini: in_sockinfo) -> Bool {
        if ini.insi_vflag & UInt8(INI_IPV4) != 0 {
            let a = ini.insi_faddr.ina_46.i46a_addr4.s_addr
            return UInt32(bigEndian: a) >> 24 == 127
        }
        return withUnsafeBytes(of: ini.insi_faddr.ina_6) { $0.elementsEqual([UInt8](repeating: 0, count: 15) + [1]) }
    }

    /// Open regular files: name only, whether open for writing, and age of last change.
    public static func files(_ pid: Int32, now: Double = Date().timeIntervalSince1970) -> [FileFact] {
        var out: [FileFact] = []
        for fd in fds(pid) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var vi = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &vi, size) == size else { continue }
            let path = withUnsafeBytes(of: vi.pvip.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let mode = vi.pvip.vip_vi.vi_stat.vst_mode
            guard mode & S_IFMT == S_IFREG else { continue }
            let mtime = Double(vi.pvip.vip_vi.vi_stat.vst_mtime)
            out.append(
                FileFact(
                    name: (path as NSString).lastPathComponent,
                    openForWriting: vi.pfi.fi_openflags & UInt32(FWRITE) != 0,
                    secondsSinceModified: max(0, now - mtime)))
        }
        return out
    }
}
