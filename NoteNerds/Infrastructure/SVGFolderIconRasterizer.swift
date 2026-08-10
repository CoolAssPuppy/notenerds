import Foundation
import UIKit
import WebKit

struct SVGFolderIconValidator {
    private let maximumElementCount: Int

    init(maximumElementCount: Int) {
        self.maximumElementCount = maximumElementCount
    }

    func validate(_ source: String) throws {
        let lowered = source.lowercased()
        guard !lowered.contains("<!doctype"), !lowered.contains("<!entity") else {
            throw FolderIconImportError.unsafeSVG
        }
        let delegate = SVGXMLValidationDelegate(maximumElementCount: maximumElementCount)
        let parser = XMLParser(data: Data(source.utf8))
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse(), delegate.didFindSVGRoot else {
            throw delegate.validationError ?? FolderIconImportError.invalidImage
        }
        if let validationError = delegate.validationError {
            throw validationError
        }
    }
}

private final class SVGXMLValidationDelegate: NSObject, XMLParserDelegate {
    private static let forbiddenElements: Set<String> = [
        "audio", "body", "button", "canvas", "embed", "foreignobject", "form",
        "head", "html", "iframe", "image", "img", "input", "link", "math",
        "meta", "object", "script", "select", "source", "style", "textarea",
        "track", "video"
    ]
    private static let forbiddenResourceAttributes: Set<String> = [
        "action", "formaction", "poster", "src", "srcset"
    ]

    private let maximumElementCount: Int
    private var depth = 0
    private var elementCount = 0
    private(set) var didFindSVGRoot = false
    private(set) var validationError: FolderIconImportError?

    init(maximumElementCount: Int) {
        self.maximumElementCount = maximumElementCount
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(qName ?? elementName)
        if depth == 0 {
            guard name == "svg" else {
                stop(parser, with: .invalidImage)
                return
            }
            didFindSVGRoot = true
        }
        depth += 1
        elementCount += 1
        guard elementCount <= maximumElementCount,
              !Self.forbiddenElements.contains(name) else {
            stop(parser, with: .unsafeSVG)
            return
        }

        for (rawName, rawValue) in attributeDict {
            let attributeName = localName(rawName)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if attributeName.hasPrefix("on") && attributeName.count > 2 {
                stop(parser, with: .unsafeSVG)
                return
            }
            if Self.forbiddenResourceAttributes.contains(attributeName) {
                stop(parser, with: .unsafeSVG)
                return
            }
            if attributeName == "href", !value.hasPrefix("#") {
                stop(parser, with: .unsafeSVG)
                return
            }
            if value.localizedCaseInsensitiveContains("@import") || containsExternalURL(value) {
                stop(parser, with: .unsafeSVG)
                return
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        depth -= 1
    }

    func parser(
        _ parser: XMLParser,
        foundProcessingInstructionWithTarget target: String,
        data: String?
    ) {
        stop(parser, with: .unsafeSVG)
    }

    private func containsExternalURL(_ value: String) -> Bool {
        var remainder = value[...]
        while let start = remainder.range(of: "url(", options: .caseInsensitive) {
            let afterStart = remainder[start.upperBound...]
            guard let end = afterStart.firstIndex(of: ")") else { return true }
            let target = String(afterStart[..<end]).trimmingCharacters(
                in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))
            )
            guard target.hasPrefix("#") else { return true }
            remainder = afterStart[afterStart.index(after: end)...]
        }
        return false
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    private func stop(_ parser: XMLParser, with error: FolderIconImportError) {
        guard validationError == nil else { return }
        validationError = error
        parser.abortParsing()
    }
}

@MainActor
final class SVGFolderIconRasterizer: NSObject, WKNavigationDelegate {
    private let pixelSize: Int
    private let webView: WKWebView
    private var continuation: CheckedContinuation<Void, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var snapshotContinuation: CheckedContinuation<UIImage, any Error>?
    private var snapshotTimeoutTask: Task<Void, Never>?

    init(pixelSize: Int) {
        self.pixelSize = pixelSize
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            configuration: configuration
        )
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.isUserInteractionEnabled = false
        webView.underPageBackgroundColor = .clear
    }

    func image(from source: String) async throws -> UIImage {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.loadHTMLString(html(source: source), baseURL: nil)
                timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    self?.finish(.failure(FolderIconImportError.invalidImage))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }

        return try await snapshot()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.scheme == "about" ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        finish(.failure(FolderIconImportError.invalidImage))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        finish(.failure(FolderIconImportError.invalidImage))
    }

    private func html(source: String) -> String {
        let iconSize = pixelSize - 8
        let encodedSource = Data(source.utf8).base64EncodedString()
        return """
        <!doctype html>
        <html>
          <head>
            <meta
              http-equiv="Content-Security-Policy"
              content="default-src 'none'; img-src data:; style-src 'unsafe-inline'"
            >
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
              body { display: flex; align-items: center; justify-content: center; }
              body > img { width: \(iconSize)px; height: \(iconSize)px; object-fit: contain; }
            </style>
          </head>
          <body><img alt="" src="data:image/svg+xml;base64,\(encodedSource)"></body>
        </html>
        """
    }

    private func finish(_ result: Result<Void, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        if case .failure = result { webView.stopLoading() }
        continuation.resume(with: result)
    }

    private func snapshot() async throws -> UIImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        configuration.afterScreenUpdates = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                snapshotContinuation = continuation
                snapshotTimeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(3))
                        self?.finishSnapshot(.failure(FolderIconImportError.invalidImage))
                    } catch {}
                }
                webView.takeSnapshot(with: configuration) { [weak self] image, error in
                    if let image {
                        self?.finishSnapshot(.success(image))
                    } else {
                        self?.finishSnapshot(.failure(error ?? FolderIconImportError.invalidImage))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishSnapshot(.failure(CancellationError()))
            }
        }
    }

    private func finishSnapshot(_ result: Result<UIImage, any Error>) {
        guard let snapshotContinuation else { return }
        self.snapshotContinuation = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        if case .failure = result { webView.stopLoading() }
        snapshotContinuation.resume(with: result)
    }
}
