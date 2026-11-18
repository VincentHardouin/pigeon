import Foundation
import Security

/// Pushes progress to CWA's KOReader sync API (README §5).
@MainActor
final class CWA: ObservableObject {
    @Published var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @Published var username = UserDefaults.standard.string(forKey: "username") ?? ""
    @Published var lastError: String?
    private var uploading = false

    var isConfigured: Bool { !serverURL.isEmpty && !username.isEmpty && Keychain.password != nil }

    func save(password: String) {
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        UserDefaults.standard.set(username, forKey: "username")
        if !password.isEmpty { Keychain.password = password }
    }

    func uploadPending(_ store: Store) async {
        guard !uploading, let base = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), let password = Keychain.password else { return }
        uploading = true
        defer { uploading = false }
        let auth = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
        lastError = nil

        for entry in store.pending {
            do {
                let status = try await upload(entry, base: base, auth: auth)
                store.setStatus(status, for: entry.document, readAt: entry.readAt)
            } catch CWAError.unauthorized {
                lastError = "401 : identifiant ou mot de passe CWA refusé"
                return
            } catch {
                // Network or server error: the entry stays pending and is retried on the next trigger.
                lastError = error.localizedDescription
                store.setStatus(.failed(error.localizedDescription), for: entry.document, readAt: entry.readAt)
            }
        }
    }

    private func upload(_ e: ProgressEntry, base: URL, auth: String) async throws -> ProgressEntry.Status {
        // CWA stamps progress with its receive time, so a late relay must not overwrite a newer read made elsewhere.
        var get = request(base.appendingPathComponent("kosync/syncs/progress/\(e.document)"), auth: auth)
        get.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: get)
        try check(response)
        if let server = try? JSONDecoder().decode(ServerProgress.self, from: data),
           let ts = server.timestamp, Date(timeIntervalSince1970: ts) >= e.readAt {
            return .skippedServerNewer
        }

        var put = request(base.appendingPathComponent("kosync/syncs/progress"), auth: auth)
        put.httpMethod = "PUT"
        put.setValue("application/json", forHTTPHeaderField: "Content-Type")
        put.httpBody = try JSONSerialization.data(withJSONObject: [
            "document": e.document, "progress": e.progress, "percentage": e.percentage,
            "device": e.device, "device_id": e.deviceId,
        ])
        let (_, putResponse) = try await URLSession.shared.data(for: put)
        try check(putResponse)
        return .sent(Date())
    }

    private func request(_ url: URL, auth: String) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue(auth, forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.koreader.v1+json", forHTTPHeaderField: "Accept")
        return r
    }

    private func check(_ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw CWAError.unauthorized }
        guard (200..<300).contains(code) else { throw CWAError.http(code) }
    }
}

private struct ServerProgress: Decodable { let timestamp: Double? }

enum CWAError: LocalizedError {
    case unauthorized
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .unauthorized: "401"
        case .http(let code): "HTTP \(code)"
        }
    }
}

enum Keychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "cwa"]

    static var password: String? {
        get {
            var q = query
            q[kSecReturnData as String] = true
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(query as CFDictionary)
            guard let newValue else { return }
            var q = query
            q[kSecValueData as String] = Data(newValue.utf8)
            // Readable while locked: uploads happen with the iPhone in a pocket.
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
