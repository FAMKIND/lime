// Prints the CGWindowID of the front-most normal window of the app named by the argument (default "lime"), for `screencapture -l <id>`.
// Captures only that window (never the rest of the screen). Usage: screencapture -x -o -l "$(swift mac/tools/windowshot.swift)" out.png
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "lime"
let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let mine = list.filter { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }
guard let first = mine.max(by: { (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) < (($1[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) }),
      let id = first[kCGWindowNumber as String] as? Int else { FileHandle.standardError.write(Data("no window for \(owner)\n".utf8)); exit(1) }
print(id)
