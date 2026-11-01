#if DEBUG
import UIKit

/// `-perfMeter YES` appends one line a second to Documents/perf.log: frames, dropped frames,
/// hitch time (ms past each late frame's deadline), the longest frame, and the memory footprint.
final class FrameMeter: NSObject {
    static let shared = FrameMeter()

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var dropped = 0
    private var hitch: CFTimeInterval = 0
    private var longest: CFTimeInterval = 0
    private var handle: FileHandle?

    func startIfRequested() {
        guard UserDefaults.standard.bool(forKey: "perfMeter"), link == nil else { return }
        let url = URL.documentsDirectory.appending(path: "perf.log")
        try? Data("time frames dropped hitch_ms longest_ms footprint_mb\n".utf8).write(to: url)
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let expected = link.targetTimestamp - link.timestamp
        if last > 0 {
            let delta = now - last
            frames += 1
            longest = max(longest, delta)
            if expected > 0, delta > expected * 1.5 {
                dropped += Int((delta / expected).rounded()) - 1
                hitch += delta - expected
            }
        } else {
            windowStart = now
        }
        last = now
        if now - windowStart >= 1 {
            let line = String(format: "%.1f %d %d %.1f %.1f %.1f\n", now, frames, dropped, hitch * 1000, longest * 1000,
                              Self.footprintMB())
            handle?.write(Data(line.utf8))
            windowStart = now
            frames = 0
            dropped = 0
            hitch = 0
            longest = 0
        }
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
#endif
