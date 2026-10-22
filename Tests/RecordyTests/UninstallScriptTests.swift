import Foundation
import Testing

/*
Feature: Fully uninstall Recordy
  The app, settings and system registrations are removed.
  Recordings are kept unless their deletion is explicitly requested.
*/
struct UninstallScriptTests {
    private func uninstall(_ arguments: [String] = [], commandStatus: Int = 0, home: String = "/tmp/Recordy Test Home") throws -> (status: Int32, output: String) {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/uninstall.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // All external commands are mocked, including the absolute LaunchServices path.
        process.arguments = ["-c", """
        log() { printf '<%s>' "$@"; printf '\\n'; return \(commandStatus); }
        killall() { log killall "$@"; }
        tccutil() { log tccutil "$@"; }
        osascript() { log osascript "$@"; }
        rm() { log rm "$@"; }
        find() { log find "$@"; }
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister() { log lsregister "$@"; }
        script=$1
        shift
        source "$script" "$@"
        """, "uninstall-test", script.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /*
    Scenario: Uninstall removes app data but keeps recordings
      Given Recordy has been installed
      When the user uninstalls Recordy
      Then the app, settings and registrations are removed
      And remaining matching files are reported without being deleted
      But recordings are kept
    */
    @Test("Uninstall removes app data but keeps recordings")
    func keepsRecordings() throws {
        let result = try uninstall()
        #expect(result.status == 0)
        for command in [
            "<killall><Recordy>",
            "<tccutil><reset><All><com.funivan.recordy>",
            "<tccutil><reset><All><com.recordy.app>",
            #"<osascript><-e><tell application "System Events" to delete (every login item whose name is "Recordy")>"#,
            "<lsregister><-u></Applications/Recordy.app>",
            "<rm><-rf></Applications/Recordy.app>",
            "<rm><-rf></tmp/Recordy Test Home/Library/Application Support/Recordy>",
            "<rm><-f></tmp/Recordy Test Home/Library/Preferences/com.funivan.recordy.plist>",
            "<rm><-rf></tmp/Recordy Test Home/Library/Caches/com.funivan.recordy>",
            "<rm><-rf></tmp/Recordy Test Home/Library/Saved Application State/com.funivan.recordy.savedState>",
            "<rm><-rf></tmp/Recordy Test Home/Library/HTTPStorages/com.funivan.recordy>",
            "<rm><-rf></tmp/Recordy Test Home/Library/WebKit/com.funivan.recordy>",
            "<killall><cfprefsd>",
            "<find></tmp/Recordy Test Home/Library></Library><-iname><*recordy*>"
        ] {
            #expect(result.output.contains(command))
        }
        #expect(!result.output.contains("<rm><-rf></tmp/Recordy Test Home/Movies/Recordy>"))
        #expect(result.output.contains("Kept recordings"))
        #expect(result.output.contains("Empty the Trash in Finder, then restart the Mac."))
    }

    /*
    Scenario: Recordings are deleted only when requested
      Given saved recordings exist
      When the user uninstalls with recordings
      Then the default recordings folder is removed
      And no message claims recordings were kept
    */
    @Test("Recordings are deleted only when requested")
    func deletesRecordings() throws {
        let result = try uninstall(["--with-recordings"])
        #expect(result.status == 0)
        #expect(result.output.contains("<rm><-rf></tmp/Recordy Test Home/Movies/Recordy>"))
        #expect(!result.output.contains("Kept recordings"))
    }

    /*
    Scenario: Cleanup continues when system registrations are already absent
      Given Recordy is not running and its system registrations are absent
      When the user uninstalls Recordy
      Then app data removal is still attempted
      And the final instructions are shown
    */
    @Test("Cleanup continues when system registrations are already absent")
    func continuesAfterFailures() throws {
        let result = try uninstall(commandStatus: 1)
        #expect(result.status == 0)
        #expect(result.output.contains("<rm><-rf></Applications/Recordy.app>"))
        #expect(result.output.contains("<killall><cfprefsd>"))
        #expect(result.output.contains("Empty the Trash in Finder, then restart the Mac."))
    }

    /*
    Scenario: Help and invalid options never remove data
      Given Recordy is installed
      When the user requests help or supplies an unknown option
      Then no cleanup commands run
    */
    @Test("Help and invalid options never remove data")
    func validatesArguments() throws {
        for argument in ["--help", "-h", "--unknown"] {
            let result = try uninstall([argument])
            #expect(result.status == (argument == "--unknown" ? 1 : 0))
            #expect(!result.output.contains("<"))
        }
    }

    /*
    Scenario: An empty home directory prevents cleanup
      Given the home directory is not configured
      When the user uninstalls Recordy
      Then no cleanup commands run
      And the uninstall reports an error
    */
    @Test("An empty home directory prevents cleanup")
    func requiresHome() throws {
        let result = try uninstall(home: "")
        #expect(result.status != 0)
        #expect(!result.output.contains("<rm>"))
        #expect(!result.output.contains("<killall>"))
    }

    /*
    @manual
    Scenario: macOS integrations are removed
      Given Recordy has privacy permissions and a login item on macOS
      When the user uninstalls Recordy
      Then its privacy permissions and login item are reset
      And its app is unregistered from LaunchServices
    */
}
