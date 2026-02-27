import Foundation

struct VideoFileManager {
    static func rawVideoURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("raw.mp4")
    }

    static func maskedVideoURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("masked.mp4")
    }

    static func compositeVideoURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("composite.mp4")
    }

    static func exportedVideoURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("exported.mp4")
    }

    static func backgroundMediaURL(projectID: UUID, sectionID: UUID, ext: String) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("background.\(ext)")
    }

    static func srtURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("captions.srt")
    }

    static func sectionDirectory(projectID: UUID, sectionID: UUID) -> URL {
        let dir = baseDirectory
            .appendingPathComponent("projects/\(projectID)/sections/\(sectionID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var baseDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("smashcut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
