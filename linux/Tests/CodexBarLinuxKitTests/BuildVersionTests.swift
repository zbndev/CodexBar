import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `the About pane reports the build version`() {
    #expect(LinuxAppInfo.version == BuildVersion.marketing)
}

@Test func `the build version is a plausible version string`() {
    // set-version.sh writes this file; a malformed literal would ship a
    // package whose About pane disagrees with its filename.
    let pattern = #"^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$"#
    #expect(BuildVersion.marketing.range(of: pattern, options: .regularExpression) != nil)
}
