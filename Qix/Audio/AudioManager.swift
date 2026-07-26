//
//  AudioManager.swift
//  Qix
//
//  Arcade-style SFX inspired by Taito Qix (1981).
//  Reference: https://www.youtube.com/watch?v=9Jn5Sa2nuuY
//
//  - Claim fill: one sustained low “ddaaaaddd” hum (slow/red deeper)
//  - The Qix: dual looped squares with pitch/rate/volume modulated from motion
//    (no AVAudioSourceNode — that path crashed AURemoteIO on device)
//  - Silent while drawing; fuse only when lit
//

import AVFoundation
import CoreGraphics
import Foundation

final class AudioManager {
    static let shared = AudioManager()

    private(set) var isMuted = false

    private let engine = AVAudioEngine()
    private let sfxMixer = AVAudioMixerNode()
    private let loopMixer = AVAudioMixerNode()

    private var oneshotPool: [AVAudioPlayerNode] = []
    private let fusePlayer = AVAudioPlayerNode()

    /// Two slightly detuned layers for the classic dual-line buzz.
    private let qixPlayerA = AVAudioPlayerNode()
    private let qixPlayerB = AVAudioPlayerNode()
    private let qixPitchA = AVAudioUnitTimePitch()
    private let qixPitchB = AVAudioUnitTimePitch()

    private var startBuf: AVAudioPCMBuffer?
    private var missBuf: AVAudioPCMBuffer?
    private var clearBuf: AVAudioPCMBuffer?
    private var claimFastBuf: AVAudioPCMBuffer?
    private var claimSlowBuf: AVAudioPCMBuffer?
    private var fuseBuf: AVAudioPCMBuffer?
    private var qixBuf: AVAudioPCMBuffer?

    private var sampleRate: Double = 44_100
    private var graphBuilt = false
    private var started = false
    private var qixPlaying = false
    private var fusePlaying = false
    private var audioDisabled = false

    /// Smoothed modulation state (main thread only).
    private var smoothPitch: Double = 0
    private var smoothRate: Double = 1
    private var smoothVol: Float = 0.45

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    func setMuted(_ muted: Bool) {
        isMuted = muted
        let g: Float = muted ? 0 : 1
        sfxMixer.outputVolume = g
        loopMixer.outputVolume = g
        if muted {
            qixPlayerA.volume = 0
            qixPlayerB.volume = 0
        }
    }

    func prepare() {
        _ = ensureEngine()
    }

    func playStart() {
        guard ensureEngine(), let buf = startBuf else { return }
        playOneshot(buf, volume: 0.8)
    }

    func playMissRestart() {
        guard ensureEngine(), let buf = missBuf else { return }
        stopFuse()
        playOneshot(buf, volume: 0.95)
    }

    /// Territory fill — sustained low “ddaaaaddd”.
    func playClaim(slow: Bool) {
        guard ensureEngine() else { return }
        stopFuse()
        let buf = slow ? claimSlowBuf : claimFastBuf
        guard let buf else { return }
        playOneshot(buf, volume: 0.95)
    }

    func playStageClear() {
        guard ensureEngine(), let buf = clearBuf else { return }
        stopFuse()
        smoothVol = 0.12
        qixPlayerA.volume = isMuted ? 0 : 0.08
        qixPlayerB.volume = isMuted ? 0 : 0.06
        playOneshot(buf, volume: 0.92)
    }

    // MARK: Qix

    func startQix() {
        guard ensureEngine(), let buf = qixBuf, !isMuted else { return }
        if qixPlaying {
            applyQixLevels(volA: smoothVol, volB: smoothVol * 0.85)
            return
        }

        qixPlayerA.stop()
        qixPlayerB.stop()
        qixPlayerA.scheduleBuffer(buf, at: nil, options: .loops)
        qixPlayerB.scheduleBuffer(buf, at: nil, options: .loops)

        qixPitchA.pitch = 0
        qixPitchA.rate = 1
        qixPitchB.pitch = 35 // ~1/3 semitone up
        qixPitchB.rate = 1.01

        smoothPitch = 0
        smoothRate = 1
        smoothVol = 0.45
        applyQixLevels(volA: smoothVol, volB: smoothVol * 0.85)

        qixPlayerA.play()
        qixPlayerB.play()
        qixPlaying = true
    }

    func stopQix() {
        qixPlaying = false
        qixPlayerA.stop()
        qixPlayerB.stop()
    }

    /// Drive the Qix voice from live Helix motion (main thread / game loop only).
    func updateQix(
        mid: CGPoint,
        player: CGPoint,
        screenWidth: CGFloat,
        mode: HelixMode,
        segmentLength: CGFloat,
        minLen: CGFloat,
        maxLen: CGFloat,
        omega: CGFloat,
        endpointSpeed: CGFloat,
        endpointSpeedDelta: CGFloat
    ) {
        guard qixPlaying, !isMuted, started else { return }

        let dx = mid.x - player.x
        let dist = hypot(dx, mid.y - player.y)
        let near = max(0, min(1, 1 - dist / max(screenWidth * 0.7, 1)))
        let near2 = near * near

        // Length → pitch (short = higher)
        let lenT = max(0, min(1, Double((segmentLength - minLen) / max(maxLen - minLen, 1))))
        var targetPitch = (1 - lenT) * 280.0 // cents up when short

        // Spin + speed → rate and extra pitch animation
        let spin = min(1, Double(omega) / 4.0)
        let speedT = min(1, Double(endpointSpeed) / 280.0)
        let asym = min(1, Double(endpointSpeedDelta) / 200.0)

        var targetRate = 0.92 + speedT * 0.22 + spin * 0.18
        var targetVol = 0.28 + Float(near2) * 0.2 + Float(speedT) * 0.18

        // Second layer detune tracks asymmetry (fan / lead end)
        var layerBCents = 25.0 + asym * 90.0 + spin * 40.0

        switch mode {
        case .loiter:
            targetVol *= 0.7
            targetRate = 0.88 + speedT * 0.08
            targetPitch *= 0.7
        case .wander:
            // Gentle continuous drift so it never sits still
            let t = CACurrentMediaTime()
            targetPitch += sin(t * 2.1) * 40 + sin(t * 0.7) * 25
            targetRate += sin(t * 1.3) * 0.04
        case .lunge:
            targetVol *= 1.3
            targetRate += 0.12
            targetPitch += 120
            layerBCents += 80
            // Fast tremolo via volume (updated every frame)
            let trem = Float(0.65 + 0.35 * sin(CACurrentMediaTime() * 14))
            targetVol *= trem
        }

        targetRate = max(0.75, min(1.35, targetRate))
        targetPitch = max(-200, min(500, targetPitch))
        targetVol = max(0.05, min(0.85, targetVol))

        // Smooth so pitch units don't zipper-noise
        let a = 0.18
        smoothPitch += (targetPitch - smoothPitch) * a
        smoothRate += (targetRate - smoothRate) * a
        smoothVol += (targetVol - smoothVol) * Float(a)

        qixPitchA.pitch = Float(smoothPitch)
        qixPitchA.rate = Float(smoothRate)
        qixPitchB.pitch = Float(smoothPitch + layerBCents)
        qixPitchB.rate = Float(min(1.4, smoothRate * (1.0 + asym * 0.05)))

        let pan = max(-0.4, min(0.4, Float(dx / max(screenWidth * 0.45, 1))))
        qixPlayerA.pan = pan
        qixPlayerB.pan = pan * 0.7

        applyQixLevels(volA: smoothVol, volB: smoothVol * (0.75 + Float(asym) * 0.2))
    }

    func setQixLevel(_ volume: Float) {
        smoothVol = max(0, min(1, volume))
        applyQixLevels(volA: smoothVol, volB: smoothVol * 0.85)
    }

    private func applyQixLevels(volA: Float, volB: Float) {
        guard !isMuted else {
            qixPlayerA.volume = 0
            qixPlayerB.volume = 0
            return
        }
        qixPlayerA.volume = volA
        qixPlayerB.volume = volB
    }

    // MARK: Fuse

    func startFuse() {
        guard ensureEngine(), let buf = fuseBuf, !isMuted else { return }
        if fusePlaying { return }
        fusePlayer.stop()
        fusePlayer.scheduleBuffer(buf, at: nil, options: .loops)
        fusePlayer.volume = 0.62
        fusePlayer.play()
        fusePlaying = true
    }

    func stopFuse() {
        if fusePlaying {
            fusePlayer.stop()
            fusePlaying = false
        }
    }

    func stopAllLoops() {
        stopQix()
        stopFuse()
    }

    // MARK: - Engine (crash-safe)

    @discardableResult
    private func ensureEngine() -> Bool {
        if audioDisabled { return false }
        if started, engine.isRunning { return true }

        do {
            try configureSession()
            try buildGraphIfNeeded()
            engine.prepare()
            try engine.start()
            started = true
            return true
        } catch {
            #if DEBUG
            print("Audio engine failed (disabled): \(error)")
            #endif
            audioDisabled = true
            return false
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        // Prefer hardware sample rate after session is active.
        let hw = session.sampleRate
        if hw > 1000 {
            sampleRate = hw
        }
    }

    private func buildGraphIfNeeded() throws {
        if graphBuilt { return }

        // Let the engine pick connection formats (avoids AURemoteIO format traps).
        engine.attach(sfxMixer)
        engine.attach(loopMixer)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(loopMixer, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.95

        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: sfxMixer, format: nil)
            oneshotPool.append(p)
        }

        engine.attach(fusePlayer)
        engine.connect(fusePlayer, to: loopMixer, format: nil)

        // Qix: player → timePitch → loopMixer (pitch/rate safe on main thread)
        engine.attach(qixPlayerA)
        engine.attach(qixPlayerB)
        engine.attach(qixPitchA)
        engine.attach(qixPitchB)
        engine.connect(qixPlayerA, to: qixPitchA, format: nil)
        engine.connect(qixPitchA, to: loopMixer, format: nil)
        engine.connect(qixPlayerB, to: qixPitchB, format: nil)
        engine.connect(qixPitchB, to: loopMixer, format: nil)

        qixPitchA.overlap = 8
        qixPitchB.overlap = 8

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
            ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        sampleRate = format.sampleRate

        synthesizeBuffers(format: format)
        graphBuilt = true
    }

    private func playOneshot(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard !isMuted, !oneshotPool.isEmpty else { return }
        let player = oneshotPool.first(where: { !$0.isPlaying }) ?? oneshotPool[0]
        player.stop()
        player.volume = volume
        player.pan = 0
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying {
            player.play()
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeVal)
        else { return }
        switch type {
        case .began:
            engine.pause()
        case .ended:
            do {
                try configureSession()
                try engine.start()
                if qixPlaying {
                    qixPlaying = false
                    startQix()
                }
            } catch {
                audioDisabled = true
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard !audioDisabled else { return }
        do {
            try configureSession()
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            // keep running if possible
        }
    }

    // MARK: - Buffer synthesis

    private func synthesizeBuffers(format: AVAudioFormat) {
        startBuf = makeStart(format: format)
        missBuf = makeMiss(format: format)
        clearBuf = makeStageClear(format: format)
        claimFastBuf = makeClaimBmmm(format: format, slow: false)
        claimSlowBuf = makeClaimBmmm(format: format, slow: true)
        fuseBuf = makeFuseLoop(format: format)
        qixBuf = makeQixLoop(format: format)
    }

    private func frameCount(_ seconds: Double) -> AVAudioFrameCount {
        AVAudioFrameCount((seconds * sampleRate).rounded())
    }

    private func makeBuffer(frames: AVAudioFrameCount, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buf.frameLength = frames
        if let ch = buf.floatChannelData {
            for c in 0..<Int(format.channelCount) {
                memset(ch[c], 0, Int(frames) * MemoryLayout<Float>.size)
            }
        }
        return buf
    }

    private func square(_ phase: Double) -> Double {
        var p = phase.truncatingRemainder(dividingBy: 1)
        if p < 0 { p += 1 }
        return p < 0.5 ? 1.0 : -1.0
    }

    private func crush(_ x: Double, levels: Double = 40) -> Float {
        Float(max(-1, min(1, (x * levels).rounded() / levels)))
    }

    private func writeMono(_ buf: AVAudioPCMBuffer, _ body: (_ t: Double) -> Double) {
        guard let ch = buf.floatChannelData else { return }
        let n = Int(buf.frameLength)
        let sr = sampleRate
        for i in 0..<n {
            let v = crush(body(Double(i) / sr))
            ch[0][i] = v
            if buf.format.channelCount > 1 {
                ch[1][i] = v
            }
        }
    }

    /// Seamless low dual-square base loop; pitch/rate do the motion variance.
    private func makeQixLoop(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let dur = 1.0
        guard let buf = makeBuffer(frames: frameCount(dur), format: format) else { return nil }
        var ph1 = 0.0
        var ph2 = 0.0
        writeMono(buf) { t in
            let f1 = 70.0
            let f2 = 74.5
            ph1 += f1 / sampleRate
            ph2 += f2 / sampleRate
            if ph1 >= 1 { ph1 -= floor(ph1) }
            if ph2 >= 1 { ph2 -= floor(ph2) }
            let s = 0.5 * square(ph1) + 0.4 * square(ph2)
            // Equal power-ish edge fade for seamless loop
            let edge = 0.015
            var g = 1.0
            if t < edge { g = t / edge }
            if t > dur - edge { g = (dur - t) / edge }
            return s * g * 0.55
        }
        return buf
    }

    /// One continuous low “ddaaaaddd” (not two hits that read as “ha ha”).
    /// Slow/red is deeper and slightly longer.
    private func makeClaimBmmm(format: AVAudioFormat, slow: Bool) -> AVAudioPCMBuffer? {
        let dur = slow ? 0.55 : 0.42
        let freq = slow ? 46.0 : 62.0
        guard let buf = makeBuffer(frames: frameCount(dur), format: format) else { return nil }
        var phase = 0.0
        var phaseSub = 0.0

        writeMono(buf) { t in
            let u = min(1, t / dur)
            // Slight downward settle — one long tone, no second attack
            let f = freq * (1.0 - 0.06 * u)
            phase += f / sampleRate
            phaseSub += (f * 0.5) / sampleRate
            if phase >= 1 { phase -= floor(phase) }
            if phaseSub >= 1 { phaseSub -= floor(phaseSub) }

            var s = 0.58 * sin(2 * .pi * phase)
            s += 0.38 * sin(2 * .pi * phaseSub)
            s += 0.14 * square(phase)

            let attack = 0.035
            let release = slow ? 0.16 : 0.12
            var env = 1.0
            if t < attack {
                env = t / attack
            } else if t > dur - release {
                env = max(0, (dur - t) / release)
            }
            let body = 0.88 + 0.12 * sin(.pi * min(1, t / (dur * 0.7)))
            env *= body

            return s * env * 0.92
        }
        return buf
    }

    private func makeStart(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let dur = 0.5
        guard let buf = makeBuffer(frames: frameCount(dur), format: format) else { return nil }
        let blips: [(f: Double, t0: Double, len: Double)] = [
            (330, 0.00, 0.08),
            (392, 0.10, 0.08),
            (523, 0.20, 0.14),
        ]
        writeMono(buf) { t in
            var s = 0.0
            for b in blips {
                let u = t - b.t0
                guard u >= 0, u < b.len else { continue }
                let env = u < 0.01 ? u / 0.01 : max(0, 1 - (u - 0.01) / (b.len - 0.01))
                s += 0.4 * env * square(b.f * t)
            }
            return s
        }
        return buf
    }

    /// Death / hit — long low “danggggggg” (not a short high zap).
    private func makeMiss(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let dur = 1.15
        guard let buf = makeBuffer(frames: frameCount(dur), format: format) else { return nil }
        var phase = 0.0
        var phase2 = 0.0
        writeMono(buf) { t in
            let u = min(1, t / dur)
            // Slow descending gong-like fundamental: ~110 → ~38 Hz
            let freq = 110 * pow(38.0 / 110.0, u)
            let freq2 = freq * 1.49 // rough fifth for metallic “dang”
            phase += freq / sampleRate
            phase2 += freq2 / sampleRate
            if phase >= 1 { phase -= floor(phase) }
            if phase2 >= 1 { phase2 -= floor(phase2) }

            // Soft-ish body: mostly sine + a little square grit
            var s = 0.62 * sin(2 * .pi * phase)
            s += 0.28 * sin(2 * .pi * phase2)
            s += 0.18 * square(phase)
            // Sub boom
            s += 0.35 * sin(2 * .pi * phase * 0.5)

            // Attack thump, then long ringing decay
            let attack = min(1, t / 0.02)
            let ring = exp(-t * 2.1) // hangs a while: danggggg
            let tail = max(0, 1 - u)
            let env = attack * (0.55 * ring + 0.45 * tail * tail)

            // Tiny noise only at the hit, not the whole decay
            if t < 0.05 {
                s += Double.random(in: -1...1) * 0.2 * (1 - t / 0.05)
            }

            return s * env * 0.95
        }
        return buf
    }

    private func makeStageClear(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let dur = 0.95
        guard let buf = makeBuffer(frames: frameCount(dur), format: format) else { return nil }
        let notes: [(f: Double, t0: Double, len: Double)] = [
            (262, 0.00, 0.12),
            (330, 0.10, 0.12),
            (392, 0.20, 0.12),
            (523, 0.32, 0.45),
        ]
        writeMono(buf) { t in
            var s = 0.0
            for n in notes {
                let u = t - n.t0
                guard u >= 0, u < n.len else { continue }
                let attack = min(1, u / 0.012)
                let rel = u > n.len - 0.08 ? max(0, (n.len - u) / 0.08) : 1
                s += 0.38 * attack * rel * square(n.f * t)
            }
            return s
        }
        return buf
    }

    private func makeFuseLoop(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let dur = 0.22
        guard let buf = makeBuffer(frames: frameCount(dur), format: format) else { return nil }
        var ph = 0.0
        writeMono(buf) { t in
            ph += 1800 / sampleRate
            if ph >= 1 { ph -= 1 }
            let tickGate = (t * 40).truncatingRemainder(dividingBy: 1) < 0.35 ? 1.0 : 0.0
            var s = 0.22 * square(ph) * tickGate
            s += Double.random(in: -1...1) * 0.2
            if (t * 18).truncatingRemainder(dividingBy: 1) < 0.05 {
                s += Double.random(in: -1...1) * 0.35
            }
            let edge = 0.012
            var g = 1.0
            if t < edge { g = t / edge }
            if t > dur - edge { g = (dur - t) / edge }
            return s * g * 0.7
        }
        return buf
    }
}
