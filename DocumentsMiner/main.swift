//
//  main.swift
//  ArticleMiner
//
//  Created by Kazuki Ohara on 2019/01/16.
//  Copyright © 2019 Kazuki Ohara. All rights reserved.
//

import Foundation
import Kanna

enum ElementType: String {

    case root = "(ROOT)"
    case framework = "Framework"
    case article = "Article"
    case sample = "Sample Code"
    case other = "(OTHER)"

}

struct DocumentElement: CustomStringConvertible {

    let type: ElementType
    let path: [String]
    let url: URL

    init(type: ElementType, path: [String], url: URL) {
        self.type = type
        self.path = path
        self.url = url
    }

    var description: String {
        return path.joined(separator: "/")
    }
}

func loadData(from url: URL) -> Data? {
    let directoryPath = "\(FileManager.default.temporaryDirectory.path)\(url.path)"
    let filePath = "\(directoryPath)/index.html"
    if FileManager.default.fileExists(atPath: filePath) {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
            return data
        }
    }
    guard let data = try? Data(contentsOf: url) else { return nil }
    do {
        try FileManager.default.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: URL(fileURLWithPath: filePath))
    } catch {
        // It's okay.
    }
    return data
}

var visitedURLs: Set<String> = []

func makeDocumentFromAnchorNode(_ node: Kanna.XMLElement, parentURL: URL) -> (url: URL, document: HTMLDocument)? {
    guard let href = node["href"] else { return nil }
    guard let hrefURL = URL(string: href, relativeTo: parentURL) else { return nil }

    guard !visitedURLs.contains(hrefURL.absoluteString) else { return nil }
    visitedURLs.insert(hrefURL.absoluteString)

    guard let data = loadData(from: hrefURL) else { return nil }
    do {
        let document = try HTML(html: data, encoding: .utf8)
        return (hrefURL, document)
    } catch {
        return nil
    }
}

func parseDocument(_ document: HTMLDocument, with url: URL, root: Bool = false) -> [DocumentElement] {
    let text = document.xpath("//*[@id=\"main\"]/div[1]/span").first?.text ?? ElementType.other.rawValue
    guard let type = ElementType(rawValue: text) else {
        return []
    }

    let anchorNodes: [Kanna.XMLElement]
    if root {
        let categories = [
            "app-frameworks",
            "graphics-and-games",
            "app-services",
            "media",
            "web",
            "developer-tools",
            "system"
        ].map { "@id=\"\($0)\"" }.joined(separator: "or")
        anchorNodes = document.xpath("//*[\(categories)]/div[2]/ul/li/div/a").map { $0 }
    } else {
        anchorNodes = document.xpath("//*[@id=\"topics\"]/div/div/section/div/div/div/div/div/a").map { $0 }
    }

    var elements = anchorNodes.compactMap { makeDocumentFromAnchorNode($0, parentURL: url) }
                              .flatMap { parseDocument($0.document, with: $0.url) }

    let path = document.xpath("//*[@id=\"localnav\"]/div/div/div[2]/div/div[1]/ul[1]/li[@class=\"localnav-menu-item localnav-menu-breadcrumb-item truncated\"or@class=\"localnav-menu-item localnav-menu-breadcrumb-item\"]")
                       .compactMap { $0.text }
    elements.append(DocumentElement(type: type, path: path, url: url))

    return elements
}

class TreeElement {

    let url: URL
    let title: String
    let type: ElementType
    var children: [TreeElement] = []

    init(url: URL, title: String, type: ElementType) {
        self.url = url
        self.title = title
        self.type = type
    }

    func appendChild(with path: [String], from map: [String: DocumentElement]) {
        var current = self
        for (i, title) in path.enumerated() {
            if let child = current.children.first(where: { $0.title == title }) {
                current = child
            } else if let element = map[path[0...i].joined(separator: "/")] {
                let child = TreeElement(url: element.url, title: title, type: element.type)
                current.children.append(child)
                current = child
            }
        }
    }

    func dumpAsMarkdown(headerLevel: Int, listLevel: Int) {
        switch type {
        case .other, .framework:
            guard !children.isEmpty else { break }
            print("\n\(String(repeating: "#", count: headerLevel)) [\(title)](\(url.absoluteString))")
            children.sorted { $0.title < $1.title }
                    .forEach { $0.dumpAsMarkdown(headerLevel: headerLevel + 1, listLevel: listLevel) }
        case .article, .sample:
            let listIndentWidth = 4
            print("\(String(repeating: " ", count: listLevel * listIndentWidth))* [\(title)](\(url.absoluteString))")
            children.sorted { $0.title < $1.title }
                    .forEach { $0.dumpAsMarkdown(headerLevel: headerLevel, listLevel: listLevel + 1) }
        case .root:
            children.sorted { $0.title < $1.title }
                    .forEach { $0.dumpAsMarkdown(headerLevel: headerLevel, listLevel: listLevel) }
        }
    }
}

func run() {
    guard let url = URL(string: "https://developer.apple.com/documentation") else { return }
    guard let data = loadData(from: url) else { return }
    guard let document = try? HTML(html: data, encoding: .utf8) else { return }
    let elements = parseDocument(document, with: url, root: true)
    let elementsMap = Dictionary(elements.map { ($0.description, $0) }, uniquingKeysWith: { $1 })
    let tree = TreeElement(url: url, title: "Documentation", type: .root)
    elements.filter { $0.type == .sample }
            .forEach { tree.appendChild(with: $0.path, from: elementsMap) }
    tree.dumpAsMarkdown(headerLevel: 1, listLevel: 0)
}

run()
