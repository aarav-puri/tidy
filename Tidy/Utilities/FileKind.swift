import Foundation
import UniformTypeIdentifiers

/// Coarse file classification used for filtering.
enum FileKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case video, image, audio, document, archive, diskImage, installer, application, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "Movies"
        case .image: "Pictures"
        case .audio: "Music & Audio"
        case .document: "Documents"
        case .archive: "Archives"
        case .diskImage: "Disk Images"
        case .installer: "Installers"
        case .application: "Applications"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .image: "photo"
        case .audio: "waveform"
        case .document: "doc.text"
        case .archive: "archivebox"
        case .diskImage: "externaldrive"
        case .installer: "shippingbox"
        case .application: "app"
        case .other: "doc"
        }
    }

    static func classify(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "dmg", "iso", "sparseimage", "sparsebundle", "img", "cdr", "vmdk", "qcow2", "vdi": return .diskImage
        case "pkg", "mpkg": return .installer
        case "app": return .application
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "xip": return .archive
        default: break
        }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .content) && !type.conforms(to: .executable) {
            return .document
        }
        return .other
    }

    static func kindDescription(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let desc = type.localizedDescription {
            return desc
        }
        return url.pathExtension.isEmpty ? "Document" : url.pathExtension.uppercased() + " File"
    }
}

/// Directory extensions treated as opaque packages. Scanners never descend into
/// these when looking for individual files, because removing a file inside a
/// package (for example a Photos library) would corrupt it.
enum Packages {
    static let extensions: Set<String> = [
        "app", "photoslibrary", "photolibrary", "aplibrary", "migratedphotolibrary", "musiclibrary", "tvlibrary",
        "imovielibrary", "fcpbundle", "theater", "logicx", "band", "framework", "bundle", "plugin", "kext",
        "xcodeproj", "xcworkspace", "xcarchive", "playground", "pages", "numbers", "key", "rtfd",
        "sparsebundle", "photosmigrator", "lproj", "appex", "xpc", "systemextension", "dSYM", "dsym",
        "mlpackage", "mlmodelc", "scptd", "prefPane", "saver", "qlgenerator", "mdimporter", "pkg",
        "abbu", "vcbackup", "keychain", "workflow", "pvm", "utm", "vmwarevm", "nib", "storyboardc",
    ]

    static func isPackage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension
        return !ext.isEmpty && extensions.contains(ext) || extensions.contains(ext.lowercased()) && !ext.isEmpty
    }
}
