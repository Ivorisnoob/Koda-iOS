import SwiftUI
import UIKit

/// Who the listener is on this phone: a name and a photo, nothing that leaves it.
@MainActor
@Observable
final class Profile {
    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: "koda.profile.name") }
    }
    private(set) var avatar: UIImage?

    private let avatarFile: URL

    init(directory: URL) {
        name = UserDefaults.standard.string(forKey: "koda.profile.name") ?? ""
        avatarFile = directory.appending(path: "avatar.jpg")
        avatar = (try? Data(contentsOf: avatarFile)).flatMap(UIImage.init(data:))
    }

    var displayName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Listener" : name }

    /// Initials for the placeholder avatar.
    var initials: String {
        let words = displayName.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// Store a photo, shrunk to a square 512 pixels wide.
    func setAvatar(_ data: Data?) {
        guard let data, let image = UIImage(data: data) else {
            avatar = nil
            try? FileManager.default.removeItem(at: avatarFile)
            return
        }
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let target = CGSize(width: 512, height: 512)
        let squared = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            let scale = target.width / side
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale, width: image.size.width * scale, height: image.size.height * scale))
        }
        avatar = squared
        try? squared.jpegData(compressionQuality: 0.85)?.write(to: avatarFile, options: .atomic)
    }
}

/// The listener's photo, or their initials on a gradient.
struct AvatarView: View {
    @Environment(AppModel.self) private var app
    var size: CGFloat

    var body: some View {
        ZStack {
            if let avatar = app.profile.avatar {
                Image(uiImage: avatar).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(app.profile.initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
