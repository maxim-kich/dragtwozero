import Foundation

/// Only a pointer inside an actual highlighted block preserves a scrolling selection.
func scrollPreservesSelection(at point: CGPoint, frames: [CGRect]) -> Bool {
    frames.contains { $0.contains(point) }
}

/// Leading between adjacent lines belongs to the same selected passage for
/// scrolling only. It never becomes a hover/drag hit area or a drawn highlight.
func textSelectionScrollFrames(_ frames: [CGRect]) -> [CGRect] {
    let lines = frames.sorted { $0.minY < $1.minY }
    var protected = lines
    for (first, next) in zip(lines, lines.dropFirst()) {
        let gap = next.minY - first.maxY
        guard gap > 0, gap <= max(first.height, next.height) else { continue }
        let span = first.union(next)
        protected.append(CGRect(x: span.minX, y: first.maxY, width: span.width, height: gap))
    }
    return protected
}
