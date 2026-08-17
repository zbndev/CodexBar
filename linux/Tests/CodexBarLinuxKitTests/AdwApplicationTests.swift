import CAdwaita
import Foundation
import Testing
@testable import CodexBarLinuxKit

@Test func `the adwaita application is also a gtk application`() {
    let app = AdwApplication(applicationID: "app.codexbar.linux.test")
    let type = g_type_from_name("GtkApplication")
    #expect(type != 0)
    #expect(g_type_check_instance_is_a(
        UnsafeMutablePointer<GTypeInstance>(app.pointer), type) != 0)
}
