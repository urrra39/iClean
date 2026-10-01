// ic-call-sim: stands in for a video call in iClear's lab. It runs a 10 ms timer on a
// high-priority queue (like an audio/video pipeline) and, with --audio, records from
// the default microphone and counts late buffers. Nothing is stored; samples are
// discarded. Prints "stats ..." on SIGUSR1 and every --report seconds.
import AppKit
import AudioToolbox
import Foundation

func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
setvbuf(stdout, nil, _IOLBF, 0)

let args = CommandLine.arguments
let audio = args.contains("--audio")
let report = args.firstIndex(of: "--report").flatMap { Double(args[$0 + 1]) } ?? 0
let duration = args.firstIndex(of: "--duration").flatMap { Double(args[$0 + 1]) } ?? 0

let lock = NSLock()
var jitter: [Double] = []
var glitches = 0
var buffers = 0

let q = DispatchQueue(label: "call-sim", qos: .userInteractive)
let timer = DispatchSource.makeTimerSource(flags: .strict, queue: q)
var expected = now() + 10_000_000
timer.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10), leeway: .nanoseconds(0))
timer.setEventHandler {
    let t = now()
    lock.lock()
    jitter.append(abs(Double(Int64(t) - Int64(expected))) / 1e6)
    lock.unlock()
    expected += 10_000_000
    if t > expected + 100_000_000 { expected = t + 10_000_000 }  // resync after a long gap
}
timer.resume()

// Optional microphone input: 10 ms buffers; a gap of more than 2.5 buffers is a glitch.
var queueRef: AudioQueueRef?
var lastBuffer: UInt64 = 0
if audio {
    var fmt = AudioStreamBasicDescription(
        mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
        mBitsPerChannel: 16, mReserved: 0)
    let status = AudioQueueNewInput(
        &fmt,
        { _, aq, buf, _, _, _ in
            let t = now()
            lock.lock()
            if lastBuffer > 0, Double(t - lastBuffer) / 1e6 > 25 { glitches += 1 }
            lastBuffer = t
            buffers += 1
            lock.unlock()
            AudioQueueEnqueueBuffer(aq, buf, 0, nil)
        }, nil, nil, nil, 0, &queueRef)
    if status == noErr, let aq = queueRef {
        for _ in 0..<4 {
            var b: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(aq, 960, &b)
            if let b { AudioQueueEnqueueBuffer(aq, b, 0, nil) }
        }
        let s = AudioQueueStart(aq, nil)
        print("audio start status=\(s)")
    } else {
        print("audio unavailable status=\(status)")
    }
}

func printStats() {
    lock.lock()
    let s = jitter.sorted()
    let g = glitches
    let b = buffers
    jitter.removeAll(keepingCapacity: true)
    glitches = 0
    buffers = 0
    lock.unlock()
    func p(_ x: Double) -> Double { s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count - 1) * x))] }
    print(
        String(
            format: "stats n=%d p50=%.3f p95=%.3f p99=%.3f max=%.3f buffers=%d glitches=%d",
            s.count, p(0.5), p(0.95), p(0.99), s.last ?? 0, b, g))
}

signal(SIGUSR1, SIG_IGN)
let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
usr1.setEventHandler { printStats() }
usr1.resume()
if report > 0 {
    let r = DispatchSource.makeTimerSource(queue: .main)
    r.schedule(deadline: .now() + report, repeating: report)
    r.setEventHandler { printStats() }
    r.resume()
}
let parent = getppid()
let watch = DispatchSource.makeTimerSource(queue: .main)
watch.schedule(deadline: .now() + 1, repeating: 1)
watch.setEventHandler { if getppid() != parent { exit(0) } }
watch.resume()
if duration > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        printStats()
        exit(0)
    }
}
print("ready pid=\(getpid())")
// --app: a regular app (Dock icon, no window), so iClear sees it as a call app.
if CommandLine.arguments.contains("--app") {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.run()
}
dispatchMain()
