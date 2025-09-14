import Foundation
import CoreMotion
import os.log

/// Tracks temporal stability of serial number candidates across multiple frames
@available(iOS 13.0, *)
class StabilityTracker {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "StabilityTracker")
    
    // Tracking state
    private var candidateHistory: [TimestampedCandidate] = []
    private var currentStableCandidate: String?
    private var stabilityStartTime: Date?
    
    // Configuration
    private let maxHistorySize: Int = 10
    private let requiredStableFrames: Int = 3
    private let maxEditDistance: Int = 1
    private let stabilityWindowDuration: TimeInterval = 1.0
    private let lockDuration: TimeInterval = 2.0
    
    // Motion detection
    private let motionManager = CMMotionManager()
    private var lastMotionReading: CMDeviceMotion?
    private let motionThreshold: Double = 0.1
    
    // State tracking
    private(set) var currentState: StabilityState = .seeking
    private var lockedTime: Date?
    
    init() {
        setupMotionDetection()
        logger.debug("StabilityTracker initialized")
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
    
    private func setupMotionDetection() {
        guard motionManager.isDeviceMotionAvailable else {
            logger.warning("Device motion not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.lastMotionReading = motion
        }
    }
    
    /// Tracks candidate stability across frames
    func trackCandidate(_ candidate: ValidatedCandidate) -> StabilityResult {
        let timestamp = Date()
        
        // Check if device is stable enough for tracking
        guard isDeviceStable() else {
            return StabilityResult(
                state: .seeking,
                stableCandidate: nil,
                guidanceMessage: "Hold device steady",
                shouldLock: false,
                confidence: 0.0
            )
        }
        
        // Add to history
        let timestampedCandidate = TimestampedCandidate(
            candidate: candidate,
            timestamp: timestamp
        )
        candidateHistory.append(timestampedCandidate)
        
        // Maintain history size
        if candidateHistory.count > maxHistorySize {
            candidateHistory.removeFirst()
        }
        
        // Analyze stability
        return analyzeStability()
    }
    
    private func isDeviceStable() -> Bool {
        guard let motion = lastMotionReading else { return true } // Assume stable if no motion data
        
        let acceleration = motion.userAcceleration
        let rotationRate = motion.rotationRate
        
        let totalAcceleration = sqrt(
            pow(acceleration.x, 2) +
            pow(acceleration.y, 2) +
            pow(acceleration.z, 2)
        )
        
        let totalRotation = sqrt(
            pow(rotationRate.x, 2) +
            pow(rotationRate.y, 2) +
            pow(rotationRate.z, 2)
        )
        
        return totalAcceleration < motionThreshold && totalRotation < motionThreshold
    }
    
    private func analyzeStability() -> StabilityResult {
        guard candidateHistory.count >= requiredStableFrames else {
            currentState = .seeking
            return StabilityResult(
                state: .seeking,
                stableCandidate: nil,
                guidanceMessage: "Scanning for serial number...",
                shouldLock: false,
                confidence: 0.0
            )
        }
        
        // Get recent candidates
        let recentCandidates = Array(candidateHistory.suffix(5))
        
        // Find consensus candidate
        if let consensus = findConsensusCandidate(recentCandidates) {
            let stability = calculateStability(for: consensus.serial, in: recentCandidates)
            
            if stability >= 0.8 {
                // Check if we should lock
                if currentState == .stabilized {
                    if let stabilityStart = stabilityStartTime,
                       Date().timeIntervalSince(stabilityStart) >= stabilityWindowDuration {
                        currentState = .locked
                        lockedTime = Date()
                        
                        return StabilityResult(
                            state: .locked,
                            stableCandidate: consensus.serial,
                            guidanceMessage: "Serial number captured!",
                            shouldLock: true,
                            confidence: consensus.confidence
                        )
                    }
                } else {
                    currentState = .stabilized
                    stabilityStartTime = Date()
                    currentStableCandidate = consensus.serial
                }
                
                return StabilityResult(
                    state: .stabilized,
                    stableCandidate: consensus.serial,
                    guidanceMessage: "Hold steady to confirm...",
                    shouldLock: false,
                    confidence: consensus.confidence
                )
            } else {
                currentState = .candidate
                return StabilityResult(
                    state: .candidate,
                    stableCandidate: consensus.serial,
                    guidanceMessage: "Potential serial detected",
                    shouldLock: false,
                    confidence: consensus.confidence
                )
            }
        }
        
        currentState = .seeking
        return StabilityResult(
            state: .seeking,
            stableCandidate: nil,
            guidanceMessage: "Scanning for serial number...",
            shouldLock: false,
            confidence: 0.0
        )
    }
    
    private func findConsensusCandidate(_ candidates: [TimestampedCandidate]) -> StableCandidate? {
        // Group candidates by edit distance similarity
        var groups: [String: [TimestampedCandidate]] = [:]
        
        for candidate in candidates {
            let serial = candidate.candidate.validation.cleanedSerial
            var foundGroup = false
            
            for groupKey in groups.keys {
                if levenshteinDistance(serial, groupKey) <= maxEditDistance {
                    groups[groupKey]?.append(candidate)
                    foundGroup = true
                    break
                }
            }
            
            if !foundGroup {
                groups[serial] = [candidate]
            }
        }
        
        // Find the largest group
        guard let bestGroup = groups.max(by: { $0.value.count < $1.value.count }) else {
            return nil
        }
        
        // Calculate average confidence for the group
        let totalConfidence = bestGroup.value.reduce(0) { $0 + $1.candidate.compositeScore }
        let averageConfidence = totalConfidence / Float(bestGroup.value.count)
        
        return StableCandidate(
            serial: bestGroup.key,
            confidence: averageConfidence,
            frameCount: bestGroup.value.count,
            firstDetected: bestGroup.value.first?.timestamp ?? Date(),
            lastDetected: bestGroup.value.last?.timestamp ?? Date()
        )
    }
    
    private func calculateStability(for serial: String, in candidates: [TimestampedCandidate]) -> Float {
        let matchingCandidates = candidates.filter {
            levenshteinDistance($0.candidate.validation.cleanedSerial, serial) <= maxEditDistance
        }
        
        let stabilityRatio = Float(matchingCandidates.count) / Float(candidates.count)
        
        // Boost stability if candidates are recent and consistent
        let timeSpan = candidates.last?.timestamp.timeIntervalSince(candidates.first?.timestamp ?? Date()) ?? 0
        let timeBonus: Float = timeSpan > 0.5 ? 0.1 : 0.0
        
        return min(1.0, stabilityRatio + timeBonus)
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = (a[i-1] == b[j-1]) ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    /// Checks if currently in locked state
    func isLocked() -> Bool {
        if currentState == .locked,
           let lockTime = lockedTime,
           Date().timeIntervalSince(lockTime) < lockDuration {
            return true
        }
        
        // Auto-unlock after lock duration
        if currentState == .locked {
            reset()
        }
        
        return false
    }
    
    /// Forces unlock for user intervention
    func forceUnlock() {
        reset()
        logger.debug("StabilityTracker force unlocked")
    }
    
    /// Resets tracking state
    func reset() {
        candidateHistory.removeAll()
        currentStableCandidate = nil
        stabilityStartTime = nil
        currentState = .seeking
        lockedTime = nil
        logger.debug("StabilityTracker reset")
    }
    
    /// Public getter for current stability state for pipeline consumers
    func getCurrentState() -> StabilityState {
        return currentState
    }
    
    // MARK: - Supporting Types
    
    struct TimestampedCandidate {
        let candidate: ValidatedCandidate
        let timestamp: Date
    }
    
    struct StableCandidate {
        let serial: String
        let confidence: Float
        let frameCount: Int
        let firstDetected: Date
        let lastDetected: Date
    }
}
