import Foundation

enum PersonalInfoRedactor {
    private static let emailPattern = try! NSRegularExpression(
        pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
        options: .caseInsensitive
    )

    static func redactEmails(in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return emailPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "Hidden")
    }

    static func conditionalRedact(_ text: String?, hideInfo: Bool) -> String? {
        guard hideInfo else { return text }
        guard text != nil else { return nil }
        return "Hidden"
    }
}
