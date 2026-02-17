import Foundation

func sbFormatDuration(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

func sbFormatDurationPrecise(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    let tenths = Int((seconds * 10).truncatingRemainder(dividingBy: 10))
    return String(format: "%02d:%02d.%d", mins, secs, tenths)
}
