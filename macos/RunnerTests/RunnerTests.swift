import Cocoa
import FlutterMacOS
import XCTest
@testable import CloudMusic

class RunnerTests: XCTestCase {

  private var root: URL!
  private var cache: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .standardizedFileURL.resolvingSymlinksInPath()
    cache = root.appendingPathComponent("app_updates", isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: root)
  }

  func testAcceptsCompletedDMG() throws {
    let file = try writeFile("update.dmg")
    XCTAssertEqual(try AppUpdateFilePolicy.validatedDMG(path: file.path, directory: cache), file)
  }

  func testOfficialReleasePagePolicy() throws {
    let page = "https://github.com/KingXcode/cloud-music/releases/tag/v0.7.6-preview.1"
    XCTAssertEqual(try AppUpdateFilePolicy.validatedReleasePage(page).absoluteString, page)
    for invalid in [
      "http://github.com/KingXcode/cloud-music/releases/tag/v0.7.6",
      "https://github.com.evil.test/KingXcode/cloud-music/releases/tag/v0.7.6",
      "https://github.com/Other/project/releases/tag/v0.7.6",
      page + "?redirect=elsewhere", page + "#fragment",
      "file:///tmp/update.dmg", "https://user@github.com/KingXcode/cloud-music/releases/tag/v0.7.6"
    ] {
      XCTAssertThrowsError(try AppUpdateFilePolicy.validatedReleasePage(invalid))
    }
  }

  func testRejectsFilesOutsideExactCacheAndSiblingPrefix() throws {
    let outside = root.appendingPathComponent("outside.dmg")
    try Data("outside".utf8).write(to: outside)
    XCTAssertThrowsError(try AppUpdateFilePolicy.validatedDMG(path: outside.path, directory: cache))
    let sibling = root.appendingPathComponent("app_updates_other")
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
    let siblingFile = sibling.appendingPathComponent("update.dmg")
    try Data("outside".utf8).write(to: siblingFile)
    XCTAssertThrowsError(try AppUpdateFilePolicy.validatedDMG(path: siblingFile.path, directory: cache))
  }

  func testRejectsSymlinksTraversalAndNestedFiles() throws {
    let file = try writeFile("update.dmg")
    let link = cache.appendingPathComponent("link.dmg")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    XCTAssertThrowsError(try AppUpdateFilePolicy.validatedDMG(path: link.path, directory: cache))
    let nested = cache.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    XCTAssertThrowsError(try AppUpdateFilePolicy.validatedDMG(
      path: nested.path + "/../update.dmg", directory: cache))
    let nestedFile = nested.appendingPathComponent("update.dmg")
    try Data("nested".utf8).write(to: nestedFile)
    XCTAssertThrowsError(try AppUpdateFilePolicy.validatedDMG(path: nestedFile.path, directory: cache))
  }

  func testRejectsEmptyPartialMissingAndRelativeFiles() throws {
    let empty = try writeFile("empty.dmg", contents: "")
    let partial = try writeFile("update.dmg.part")
    for path in [empty.path, partial.path, cache.path + "/missing.dmg", "update.dmg"] {
      XCTAssertThrowsError(try AppUpdateFilePolicy.validatedDMG(path: path, directory: cache))
    }
  }

  func testQuarantineIsAddedAndPreserved() throws {
    let file = try writeFile("update.dmg")
    try AppUpdateFilePolicy.quarantineDownload(file)
    let first = try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.quarantinePropertiesKey])
      .quarantineProperties
    XCTAssertNotNil(first)
    try AppUpdateFilePolicy.quarantineDownload(file)
    let second = try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.quarantinePropertiesKey])
      .quarantineProperties
    XCTAssertEqual(first as NSDictionary?, second as NSDictionary?)
  }

  private func writeFile(_ name: String, contents: String = "test disk image") throws -> URL {
    let file = cache.appendingPathComponent(name)
    try Data(contents.utf8).write(to: file)
    return file
  }

}
