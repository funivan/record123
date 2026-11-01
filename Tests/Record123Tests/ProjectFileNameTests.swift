import Testing
import Foundation
@testable import Record123

/*
Feature: A project can only reference files inside its own folder
  File names in project.json are joined onto the project folder, so a name
  that points elsewhere would let a shared recording read unrelated files.
*/
struct ProjectFileNameTests {
    private func load(_ edit: (inout Project) -> Void) throws -> Project {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var p = Project(name: "a", duration: 1)
        edit(&p)
        try ProjectIO.save(p, to: dir)
        return try ProjectIO.load(dir)
    }

    /*
    Scenario: A project with plain file names opens
      Given a project whose files sit directly in its folder
      When the project is opened
      Then it loads
    */
    @Test("A project with plain file names opens")
    func plainNamesLoad() throws {
        let p = try load { $0.micFile = "mic.m4a" }
        #expect(p.micFile == "mic.m4a")
    }

    /*
    Scenario: A project referencing a file outside its folder is rejected
      Given a project that points at a file outside its folder
      When the project is opened
      Then opening fails
    */
    @Test("A project referencing a file outside its folder is rejected")
    func traversalRejected() {
        #expect(throws: ProjectError.self) { try load { $0.style.bgImageFile = "../../Pictures/secret.png" } }
        #expect(throws: ProjectError.self) { try load { $0.style.bgImageFile = "/etc/hosts" } }
        #expect(throws: ProjectError.self) { try load { $0.screenFile = "../x.mov" } }
        #expect(throws: ProjectError.self) { try load { $0.cameraFile = "sub/camera.mov" } }
    }
}
