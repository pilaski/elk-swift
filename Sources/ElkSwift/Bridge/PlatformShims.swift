// Where there is no `os` module (Windows, Linux): the few os_unfair_lock
// calls the engine makes, on an NSLock.
#if !canImport(os)
import Foundation

struct os_unfair_lock {
    let lock = NSLock()
}

typealias os_unfair_lock_t = UnsafeMutablePointer<os_unfair_lock>

@inline(__always) func os_unfair_lock_lock(_ lock: os_unfair_lock_t) { lock.pointee.lock.lock() }
@inline(__always) func os_unfair_lock_unlock(_ lock: os_unfair_lock_t) { lock.pointee.lock.unlock() }
#endif

#if !canImport(CoreFoundation) || os(Windows)
typealias CFAbsoluteTime = Double
@inline(__always) func CFAbsoluteTimeGetCurrent() -> CFAbsoluteTime { Date().timeIntervalSinceReferenceDate }
#endif

#if os(Windows)
// The C runtime declares it only with _USE_MATH_DEFINES.
let M_E: Double = 2.718281828459045
#endif
