import Foundation
import Vision
import os.log

/// Multi-frame consensus engine for serial number recognition
/// Provides sophisticated frame-by-frame analysis and stability tracking
class MultiFrameConsensusEngine {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "ConsensusEngine")
    
    // Consensus configuration
    private let bufferSize: Int
    private let minimumFramesForConsensus: Int
    private let stabilityThreshold: TimeInterval
    private let confidenceThreshold: Float
    
    // Frame buffer and state tracking (use types from ConsensusAnalytics)
    private var frameBuffer: [ConsensusAnalytics.SerialCandidate] = []
    private var currentConsensus: ConsensusAnalytics.SerialConsensus?
    private var stabilityStartTime: TimeInterval?
    private var analyticsCollector = SimpleConsensusAnalyticsCollector()
    
    init(bufferSize: Int = 15,
         minimumFramesForConsensus: Int = 5,
         stabilityThreshold: TimeInterval = 1.5,
         confidenceThreshold: Float = 0.75) {
        self.bufferSize = bufferSize
        self.minimumFramesForConsensus = minimumFramesForConsensus
        self.stabilityThreshold = stabilityThreshold
        self.confidenceThreshold = confidenceThreshold
    }
    
    /// Process a new frame of serial number candidates
    func processFrame(
        candidates: [ConsensusAnalytics.SerialCandidate],
        timestamp: TimeInterval,
        completion: @escaping (ConsensusAnalytics.ConsensusResult) -> Void
    ) {
        // Add new candidates to buffer
        frameBuffer.append(contentsOf: candidates)
        
        // Maintain buffer size
        if frameBuffer.count > bufferSize {
            frameBuffer.removeFirst(frameBuffer.count - bufferSize)
        }
        
        // Analyze current consensus state
        let result = analyzeConsensus(at: timestamp)
        
        // Collect analytics
        analyticsCollector.record(result: result)
        
        // Return result
        completion(result)
    }
    
    /// Reset the consensus engine state
    func reset() {
        frameBuffer.removeAll()
        currentConsensus = nil
        stabilityStartTime = nil
        analyticsCollector.reset()
        logger.info("Consensus engine reset")
    }
    
    // MARK: - Private Methods
    
    private func analyzeConsensus(at timestamp: TimeInterval) -> ConsensusAnalytics.ConsensusResult {
        guard frameBuffer.count >= minimumFramesForConsensus else {
            return ConsensusAnalytics.ConsensusResult(
                stabilityState: .accumulating,
                consensus: nil,
                overallConfidence: 0,
                frameCount: frameBuffer.count
            )
        }
        
        // Group candidates by text
        let grouped = Dictionary(grouping: frameBuffer) { $0.text }
        
        // Find most frequent text
        guard let mostFrequent = grouped.max(by: { $0.value.count < $1.value.count }) else {
            return ConsensusAnalytics.ConsensusResult(
                stabilityState: .unstable,
                consensus: nil,
                overallConfidence: 0,
                frameCount: frameBuffer.count
            )
        }
        
        // Calculate consensus metrics
        let consensusText = mostFrequent.key
        let consensusCandidates = mostFrequent.value
        let consensusConfidence = consensusCandidates.reduce(0) { $0 + $1.confidence } / Float(consensusCandidates.count)
        
        // Check if consensus meets confidence threshold
        guard consensusConfidence >= confidenceThreshold else {
            return ConsensusAnalytics.ConsensusResult(
                stabilityState: .unstable,
                consensus: nil,
                overallConfidence: consensusConfidence,
                frameCount: frameBuffer.count
            )
        }
        
        // Update stability tracking
        if currentConsensus?.serialText != consensusText {
            stabilityStartTime = timestamp
            currentConsensus = ConsensusAnalytics.SerialConsensus(
                serialText: consensusText,
                overallConfidence: consensusConfidence,
                stabilityDuration: 0,
                frameCount: consensusCandidates.count
            )
            return ConsensusAnalytics.ConsensusResult(
                stabilityState: .stabilizing,
                consensus: currentConsensus,
                overallConfidence: consensusConfidence,
                frameCount: frameBuffer.count
            )
        }
        
        // Calculate stability duration
        guard let startTime = stabilityStartTime else {
            return ConsensusAnalytics.ConsensusResult(
                stabilityState: .unstable,
                consensus: nil,
                overallConfidence: consensusConfidence,
                frameCount: frameBuffer.count
            )
        }
        
        let stabilityDuration = timestamp - startTime
        
        // Update current consensus
        currentConsensus = ConsensusAnalytics.SerialConsensus(
            serialText: consensusText,
            overallConfidence: consensusConfidence,
            stabilityDuration: stabilityDuration,
            frameCount: consensusCandidates.count
        )
        
        // Determine stability state
        let stabilityState: ConsensusAnalytics.StabilityState
        if stabilityDuration >= stabilityThreshold {
            stabilityState = consensusConfidence >= 0.95 ? .locked : .stable
        } else {
            stabilityState = .stabilizing
        }
        
        return ConsensusAnalytics.ConsensusResult(
            stabilityState: stabilityState,
            consensus: currentConsensus,
            overallConfidence: consensusConfidence,
            frameCount: frameBuffer.count
        )
    }
}

// Minimal internal analytics collector to avoid missing symbol errors
private class SimpleConsensusAnalyticsCollector {
    func record(result: ConsensusAnalytics.ConsensusResult) {
        // lightweight recording for analytics
    }
    
    func reset() {
        // reset internal state if needed (no-op for now)
    }
}
