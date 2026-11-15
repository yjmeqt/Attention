import CryptoKit
import DeviceCheck
import Foundation

/// App Attest for list uploads (web/src/attest.ts): a key in the Secure Enclave, attested by Apple once,
/// signs each upload so the server knows it comes from Attention on a real device.
enum AppAttest {
    private static let keyIDDefaultsKey = "appAttestKeyID"
    static let attestURL = URL(string: "https://attentioncard.com/api/attest")!
    static let challengeURL = URL(string: "https://attentioncard.com/api/attest/challenge")!

    /// `X-Attest-*` headers signing `listJSON`. Empty where the device can't attest (simulators) or anything
    /// fails; the server's ATTEST_MODE decides whether that upload still goes through.
    static func headers(for listJSON: Data, session: URLSession = .shared) async -> [String: String] {
        let service = DCAppAttestService.shared
        guard service.isSupported else { return [:] }
        do {
            let keyID = try await attestedKey(service, session: session)
            let challenge = try await fetchChallenge(session: session)
            let assertion = try await service.generateAssertion(keyID, clientDataHash: uploadClientDataHash(challenge: challenge, listJSON: listJSON))
            return ["X-Attest-Key": keyID, "X-Attest-Challenge": challenge, "X-Attest-Assertion": assertion.base64EncodedString()]
        } catch {
            // The Secure Enclave lost the key (a restore to another device): make a new one next time.
            if (error as? DCError)?.code == .invalidKey { forget() }
            return [:]
        }
    }

    /// Drops the key, for when the server no longer knows it; the next upload attests a new one.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: keyIDDefaultsKey)
    }

    /// What the server checks the assertion against: the challenge and the list's JSON, so it can't be reused.
    static func uploadClientDataHash(challenge: String, listJSON: Data) -> Data {
        let listHash = SHA256.hash(data: listJSON).map { String(format: "%02x", $0) }.joined()
        return Data(SHA256.hash(data: Data("\(challenge).\(listHash)".utf8)))
    }

    private static func attestedKey(_ service: DCAppAttestService, session: URLSession) async throws -> String {
        if let keyID = UserDefaults.standard.string(forKey: keyIDDefaultsKey) { return keyID }
        let keyID = try await service.generateKey()
        let challenge = try await fetchChallenge(session: session)
        let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        var request = URLRequest(url: attestURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["keyId": keyID, "attestation": attestation.base64EncodedString(), "challenge": challenge])
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw URLError(.badServerResponse) }
        // Kept only once the server has the key; until then every upload tries again.
        UserDefaults.standard.set(keyID, forKey: keyIDDefaultsKey)
        return keyID
    }

    private static func fetchChallenge(session: URLSession) async throws -> String {
        var request = URLRequest(url: challengeURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([String: String].self, from: data)["challenge"] ?? { throw URLError(.badServerResponse) }()
    }
}
