import CryptoKit
import Foundation
import UIKit

enum PilotCrypto {
    struct EncryptedPhoto {
        var ciphertext: Data
        var sha256: String
    }

    static func makeSubmissionKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func normalizedJPEG(from image: UIImage) throws -> Data {
        let normalized = PhotoStore.prepare(image).image
        guard let data = normalized.jpegData(compressionQuality: 0.88) else {
            throw PilotStudyError.photoUnavailable
        }
        return data
    }

    static func encryptPhoto(_ plaintext: Data, using key: SymmetricKey) throws -> EncryptedPhoto {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw PilotStudyError.storageFailed }
        return EncryptedPhoto(ciphertext: combined, sha256: sha256Hex(combined))
    }

    static func wrap(
        submissionKey: SymmetricKey,
        publicKeyBase64: String = PilotStudyConfiguration.keyAgreementPublicKeyBase64
    ) throws -> PilotWrappedKeyEnvelope {
        guard let publicData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? P256.KeyAgreement.PublicKey(x963Representation: publicData) else {
            throw PilotStudyError.invalidStudyKey
        }
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw PilotStudyError.storageFailed }
        let wrappingKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("evolv-pilot-wrap-v1".utf8),
            outputByteCount: 32
        )
        let rawSubmissionKey = submissionKey.withUnsafeBytes { Data($0) }
        let sealedKey = try AES.GCM.seal(rawSubmissionKey, using: wrappingKey)
        guard let combined = sealedKey.combined else { throw PilotStudyError.storageFailed }
        return PilotWrappedKeyEnvelope(
            algorithm: "P256-HKDF-SHA256+A256GCM",
            publicKeyVersion: PilotStudyConfiguration.keyAgreementPublicKeyVersion,
            ephemeralPublicKeyBase64: ephemeral.publicKey.x963Representation.base64EncodedString(),
            saltBase64: salt.base64EncodedString(),
            sealedKeyBase64: combined.base64EncodedString()
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
