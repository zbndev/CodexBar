import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `known extensions map to mime types`() {
    #expect(WebUIProtocol.mimeType(forPathExtension: "html") == "text/html")
    #expect(WebUIProtocol.mimeType(forPathExtension: "css") == "text/css")
    #expect(WebUIProtocol.mimeType(forPathExtension: "js") == "text/javascript")
    #expect(WebUIProtocol.mimeType(forPathExtension: "svg") == "image/svg+xml")
    #expect(WebUIProtocol.mimeType(forPathExtension: "json") == "application/json")
    #expect(WebUIProtocol.mimeType(forPathExtension: "unknown") == "application/octet-stream")
}

@Test func `the index page resolves through the scheme`() {
    let resource = WebUIProtocol.resource(forURI: "codexbar://ui/index.html")
    #expect(resource != nil)
    #expect(resource?.mimeType == "text/html")
    let html = String(decoding: resource?.data ?? Data(), as: UTF8.self)
    #expect(html.contains("<!doctype html>"))
}

@Test func `every bundled page resolves`() {
    #expect(WebUIProtocol.resource(forURI: "codexbar://ui/style.css") != nil)
    #expect(WebUIProtocol.resource(forURI: "codexbar://ui/app.js") != nil)
}

@Test func `a missing file resolves to nil rather than crashing`() {
    #expect(WebUIProtocol.resource(forURI: "codexbar://ui/nope.js") == nil)
}

@Test func `path traversal outside the bundle is rejected`() {
    #expect(WebUIProtocol.resource(forURI: "codexbar://ui/../Package.swift") == nil)
    #expect(WebUIProtocol.resource(forURI: "codexbar://ui/../../etc/passwd") == nil)
}

@Test func `a different scheme resolves to nil`() {
    #expect(WebUIProtocol.resource(forURI: "https://ui/index.html") == nil)
}
