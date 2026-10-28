import Foundation

enum AppGroup {
    static var identifier: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "VaultAppGroupIdentifier") as? String
        return value?.isEmpty == false ? value : nil
    }
}
