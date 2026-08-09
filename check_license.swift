#!/usr/bin/swift
//
//  check_license.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath

let isDryRun = CommandLine.arguments.contains("--check") || CommandLine.arguments.contains("--dry-run")

guard let enumerator = fileManager.enumerator(atPath: currentPath) else {
  print("❌ Error: Unable to enumerate the current directory.")
  exit(1)
}

let dateFormatter = DateFormatter()
let yearFormatter = DateFormatter()
yearFormatter.dateFormat = "yyyy"
dateFormatter.dateFormat = "yyyy-MM-dd"

print("🛡 Auditing Alcyone Sillage source files for dynamic license headers...")

var nonCompliantCount = 0
var fixedCount = 0

let ignoredDirectories: Set<String> = [
  ".git",
  ".build",
  "build",
  "Pods",
  "DerivedData",
  ".derivedData"
]

// Regex to extract creation date from an existing header if available (e.g. Created by Alcyone on 2026-05-16.)
let dateRegex = try? NSRegularExpression(pattern: "Created by .*? on (\\d{4}-\\d{2}-\\d{2})")

while let filePath = enumerator.nextObject() as? String {
  guard filePath.hasSuffix(".swift") else { continue }
  
  let pathComponents = filePath.split(separator: "/")
  let isIgnored = pathComponents.dropLast().contains { ignoredDirectories.contains(String($0)) }
  if isIgnored { continue }
  
  let fullPath = URL(fileURLWithPath: currentPath).appendingPathComponent(filePath)
  let fileName = fullPath.lastPathComponent

  do {
    let content = try String(contentsOf: fullPath, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)
    
    // Separate shebang line if present
    var startIndex = 0
    var shebangLine: String? = nil
    if lines.indices.contains(0) && lines[0].hasPrefix("#!") {
      shebangLine = lines[0]
      startIndex = 1
    }
    
    // Skip empty lines after shebang
    while startIndex < lines.count && lines[startIndex].trimmingCharacters(in: .whitespaces).isEmpty {
      startIndex += 1
    }
    
    // Collect initial comment block
    var commentBlockEndIndex = startIndex
    var commentBlockLines: [String] = []
    while commentBlockEndIndex < lines.count {
      let line = lines[commentBlockEndIndex].trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("//") {
        commentBlockLines.append(line)
        commentBlockEndIndex += 1
      } else {
        break
      }
    }
    
    let commentBlock = commentBlockLines.joined(separator: "\n")
    
    // Strict header validation requirements
    let hasCorrectFilename = commentBlock.contains("//  \(fileName)")
    let hasProjectName = commentBlock.contains("Alcyone Sillage") || commentBlock.contains("Alcyone")
    let hasCopyright = commentBlock.contains("Copyright ©")
    let hasLicenseNotice = commentBlock.contains("This file is released under the MIT License.")
    let hasLicenseRef = commentBlock.contains("See LICENSE file in the project root for full license information.")
    
    let isValidHeader = hasCorrectFilename && hasProjectName && hasCopyright && hasLicenseNotice && hasLicenseRef
    
    if !isValidHeader {
      nonCompliantCount += 1
      
      if isDryRun {
        print("❌ Non-compliant header in: \(filePath)")
        continue
      }
      
      print("📝 Updating/Adding dynamic header in: \(filePath)")
      
      // Extract creation date if present in existing header, else fallback to file system attributes
      var dateString: String? = nil
      var yearString: String? = nil
      
      if let regex = dateRegex,
         let match = regex.firstMatch(in: commentBlock, range: NSRange(location: 0, length: commentBlock.utf16.count)),
         let dateRange = Range(match.range(at: 1), in: commentBlock) {
        let extractedDateStr = String(commentBlock[dateRange])
        if let date = dateFormatter.date(from: extractedDateStr) {
          dateString = dateFormatter.string(from: date)
          yearString = yearFormatter.string(from: date)
        }
      }
      
      if dateString == nil || yearString == nil {
        let attributes = try? fileManager.attributesOfItem(atPath: fullPath.path)
        let creationDate = (attributes?[.creationDate] as? Date) ?? Date()
        dateString = dateFormatter.string(from: creationDate)
        yearString = yearFormatter.string(from: creationDate)
      }
      
      let dynamicHeader = """
      //
      //  \(fileName)
      //  Alcyone Sillage
      //
      //  Created by Alcyone on \(dateString!).
      //  Copyright © \(yearString!) Alcyone.
      //  This file is released under the MIT License.
      //  See LICENSE file in the project root for full license information.
      //
      """
      
      // Remaining content after removing initial comment block
      let remainingLines = Array(lines[commentBlockEndIndex...])
      var remainingContent = remainingLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
      if !remainingContent.isEmpty {
        remainingContent = "\n\n" + remainingContent + "\n"
      } else {
        remainingContent = "\n"
      }
      
      var updatedContent = ""
      if let shebang = shebangLine {
        updatedContent = shebang + "\n" + dynamicHeader + remainingContent
      } else {
        updatedContent = dynamicHeader + remainingContent
      }
      
      try updatedContent.write(to: fullPath, atomically: true, encoding: .utf8)
      fixedCount += 1
    }
  } catch {
    print("⚠️ Error processing \(filePath): \(error.localizedDescription)")
  }
}

if isDryRun {
  if nonCompliantCount > 0 {
    print("❌ Audit failed: \(nonCompliantCount) non-compliant file(s) found.")
    exit(1)
  } else {
    print("✅ Audit passed: All Swift source files have valid license headers.")
  }
} else {
  print("✅ Audit complete. Fixed \(fixedCount) file(s).")
}
