// ic-media-sim: a stand-in for a music player. Plays a very quiet 440 Hz tone through
// an AudioQueue, publishes Now Playing information and answers the system's remote
// commands (media keys, Control Center). Runs as a regular app without windows.
//
//   ic-media-sim [--paused]
//     SIGUSR2: play, SIGUSR1: pause. Prints "playing", "paused" and
//     "command <name> <time>" for each remote command it receives.
import AppKit
import AudioToolbox
import Foundation
import MediaPlayer

setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.regular)

final class Tone {
    var queue: AudioQueueRef?
    var phase = 0.0
    var playing = false

    init() {
        var fmt = AudioStreamBasicDescription(
            mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        let me = Unmanaged.passUnretained(self).toOpaque()
        AudioQueueNewOutput(
            &fmt,
            { user, q, buf in
                let t = Unmanaged<Tone>.fromOpaque(user!).takeUnretainedValue()
                let n = Int(buf.pointee.mAudioDataBytesCapacity) / 4
                let p = buf.pointee.mAudioData.assumingMemoryBound(to: Float.self)
                for i in 0..<n {
                    // About -50 dBFS: barely audible, but real audio output.
                    p[i] = Float(sin(t.phase) * 0.003)
                    t.phase += 2 * .pi * 440 / 44_100
                }
                buf.pointee.mAudioDataByteSize = UInt32(n * 4)
                AudioQueueEnqueueBuffer(q, buf, 0, nil)
            }, me, nil, nil, 0, &queue)
        for _ in 0..<3 {
            var b: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(queue!, 4096 * 4, &b)
            if let b {
                b.pointee.mAudioDataByteSize = 4096 * 4
                memset(b.pointee.mAudioData, 0, 4096 * 4)
                AudioQueueEnqueueBuffer(queue!, b, 0, nil)
            }
        }
    }

    func play() {
        guard !playing, let queue else { return }
        AudioQueueStart(queue, nil)
        playing = true
        publish()
        print("playing")
    }

    func pause() {
        guard playing, let queue else { return }
        AudioQueuePause(queue)
        playing = false
        publish()
        print("paused")
    }

    func publish() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "iClear lab tone", MPMediaItemPropertyArtist: "ic-media-sim",
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }
}

let tone = Tone()
let center = MPRemoteCommandCenter.shared()
func handle(_ name: String, _ action: @escaping () -> Void) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    { _ in
        print("command \(name) \(Date().timeIntervalSince1970)")
        action()
        return .success
    }
}
center.playCommand.addTarget(handler: handle("play") { tone.play() })
center.pauseCommand.addTarget(handler: handle("pause") { tone.pause() })
center.togglePlayPauseCommand.addTarget(handler: handle("toggle") { tone.playing ? tone.pause() : tone.play() })

signal(SIGUSR1, SIG_IGN)
signal(SIGUSR2, SIG_IGN)
let pauseSrc = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
pauseSrc.setEventHandler { tone.pause() }
pauseSrc.resume()
let playSrc = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
playSrc.setEventHandler { tone.play() }
playSrc.resume()

if !CommandLine.arguments.contains("--paused") { tone.play() } else { tone.publish() }
print("ready")
withExtendedLifetime((pauseSrc, playSrc)) { app.run() }
