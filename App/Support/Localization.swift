import Foundation
import TelefonDomain

enum L10n {
    static func text(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg..., bundle: Bundle = .main) -> String {
        String(format: text(key, bundle: bundle), locale: .current, arguments: arguments)
    }

    static func error(_ error: Error) -> String {
        guard let engineError = error as? EngineError else {
            return text(error.localizedDescription)
        }
        if engineError.code == 171173 {
            return text("The phone system's TLS certificate is not trusted or does not match the server name. The connection was rejected. Check the server name, system time, and certificate with your provider.")
        }
        return format("%@ failed (code %lld). Check Diagnostics for details and connection information.",
                      text(engineError.operation), Int64(engineError.code))
    }

}
