import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Lock cooperativo entre os processos curtos da status line e o app de menu.
/// O arquivo de lock é estável (não é substituído por gravações atômicas), por
/// isso também protege corretamente operações que renomeiam o arquivo de dados.
enum FileLock {
    static func withExclusiveAccess<T>(at url: URL, _ body: () throws -> T) throws -> T {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError(path: url.path) }
        defer { close(descriptor) }

        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw posixError(path: url.path) }
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        return try body()
    }

    private static func posixError(path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSFilePathErrorKey: path]
        )
    }
}
