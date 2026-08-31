import Foundation

/// HTTPS profile-photo URLs only. Rejects blank, relative, and non-https schemes.
public enum ProfilePictureURL {
    public static func parse(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    public static func parse(from object: [String: Any]) -> URL? {
        let keys = ["pictureUrl", "pictureURL", "picture", "avatarUrl", "photoUrl", "imageUrl"]
        for key in keys {
            if let url = parse(object[key] as? String) {
                return url
            }
        }
        if let nested = object["user"] as? [String: Any] {
            return parse(from: nested)
        }
        return nil
    }
}
