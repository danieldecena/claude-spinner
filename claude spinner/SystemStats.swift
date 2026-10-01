import Combine
import Foundation

/// This Mac's CPU, memory and disk as shares of a whole, for the Usage card.
///
/// Sampled only while a card is on screen: `start()` on appear, `stop()` on
/// disappear. Every reading is optional and nil means "could not read it", never
/// zero -- the CPU share needs two samples, so it is nil until the second.
final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double?
    @Published private(set) var memory: Double?
    @Published private(set) var memoryUsedBytes: UInt64?
    @Published private(set) var disk: Double?
    @Published private(set) var diskFreeBytes: Int64?

    let memoryTotalBytes = ProcessInfo.processInfo.physicalMemory

    struct CPUTicks: Equatable {
        var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    }

    private static let interval: TimeInterval = 2
    private var timer: Timer?
    private var lastTicks: CPUTicks?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        // The next start must not diff against ticks from before the gap.
        lastTicks = nil
    }

    private func sample() {
        let ticks = Self.readCPUTicks()
        cpu = Self.cpuShare(from: lastTicks, to: ticks)
        lastTicks = ticks

        let used = Self.readMemoryUsed()
        memoryUsedBytes = used
        memory = Self.share(used: used, of: memoryTotalBytes)

        let volume = Self.readVolume()
        diskFreeBytes = volume?.free
        disk = Self.diskShare(total: volume?.total, available: volume?.free)
    }

    // MARK: - Arithmetic (no Mach calls, so it can be tested)

    /// Busy share between two tick samples. nil without a baseline, with no time
    /// elapsed, or when a counter went backwards (a wrap or a reset).
    static func cpuShare(from old: CPUTicks?, to new: CPUTicks?) -> Double? {
        guard let old, let new,
              new.user >= old.user, new.system >= old.system,
              new.idle >= old.idle, new.nice >= old.nice else { return nil }
        let busy = Double(new.user - old.user) + Double(new.system - old.system)
            + Double(new.nice - old.nice)
        let total = busy + Double(new.idle - old.idle)
        return total > 0 ? busy / total : nil
    }

    static func share(used: UInt64?, of total: UInt64) -> Double? {
        guard let used, total > 0 else { return nil }
        return min(1, Double(used) / Double(total))
    }

    static func diskShare(total: Int64?, available: Int64?) -> Double? {
        guard let total, let available, total > 0 else { return nil }
        return min(1, max(0, Double(total - available) / Double(total)))
    }

    // MARK: - Reads

    private static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
            / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        // Tuple order is CPU_STATE_USER, SYSTEM, IDLE, NICE.
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    /// Active + wired + compressed pages: what Activity Monitor's "Memory Used"
    /// counts, leaving cached files out.
    private static func readMemoryUsed() -> UInt64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
            / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let pages = UInt64(info.active_count) + UInt64(info.wire_count)
            + UInt64(info.compressor_page_count)
        return pages * UInt64(getpagesize())
    }

    private static func readVolume() -> (total: Int64, free: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Int64(total), free)
    }
}
