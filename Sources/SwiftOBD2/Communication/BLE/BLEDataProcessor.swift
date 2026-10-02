import Combine
import CoreBluetooth
import Foundation
import OSLog

class BLEMessageProcessor {
    private var buffer = Data()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.app", category: "BLEMessageProcessor")
    private var messageCompletion: (([String]?, Error?) -> Void)?

    func processReceivedData(_ data: Data) {
        obdDebug(" === Trace === In BLEMessageProcessor func  processReceivedData ")
        buffer.append(data)
 
 //sr
        obdDebug("Raw data Display length : \(data)", category: .service) //sr
        obdDebug("Appended to buffer length : \(buffer)")  //sr
        let returnedData = String(data: data, encoding: .utf8)  //sr
        obdDebug("Returned Data function says : \(returnedData)")   //sr
        let returnedBuffer = String(data: buffer, encoding: .utf8) //sr
        obdDebug("Buffer is now : \(returnedBuffer)")  //sr
//sr
        
        guard let string = String(data: buffer, encoding: .utf8) else {
            // Only clear if buffer is getting too large
            if buffer.count > BLEConstants.maxBufferSize {
                logger.warning("Buffer exceeded max size, clearing")
                buffer.removeAll()
            }
            return
        }

        // Check for end of response marker
        if string.contains(">") {
            let response = parseResponse(from: string)
            handleParsedResponse(response)
            buffer.removeAll()
        }
    }

    private func parseResponse(from string: String) -> [String] {
        obdDebug(" === Trace === In BLEMessageProcessor func  parseResponse ")
        // Split by newlines and clean up
        let lines = string
            .replacingOccurrences(of: ">", with: "") // Remove prompt marker
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        logger.debug("Parsed response: \(lines)")
        return lines
    }

    private func handleParsedResponse(_ lines: [String]) {
        obdDebug(" === Trace === In BLEMessageProcessor func  handleParsedResponse ")
       let completion = messageCompletion
       messageCompletion = nil

       guard let completion = completion else {
           logger.warning("Received response with no pending completion")
           return
       }

       if let firstLine = lines.first, firstLine.uppercased().contains("NO DATA") {
           completion(nil, BLEManagerError.noData)
       } else if lines.isEmpty {
           completion(nil, BLEManagerError.noData)
       } else {
           completion(lines, nil)
       }
   }

// original code
//    func waitForResponse(timeout: TimeInterval) async throws -> [String] {
//            try await withTimeout(seconds: timeout, timeoutError: BLEMessageProcessorError.responseTimeout) { [self] in
//                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
//
//                    // Check if there's already a pending command
//                    assert(messageCompletion == nil, "Concurrent command detected")
//
//
//                    messageCompletion = { response, error in
//                        if let response = response {
//                            obdDebug("messageCompletion response: \(response)", category: .parsing)
//                            continuation.resume(returning: response)
//                        } else if let error = error {
//                            continuation.resume(throwing: error)
//                        } else {
//                            continuation.resume(throwing: BLEMessageProcessorError.responseTimeout)
//                        }
//                    }
//
//                }
//            }
//        }


    final class SafeContinuationState {
        private var lock = os_unfair_lock_s()
        private var isResumed = false

        /// Executes the block and resumes the continuation only if it hasn't been called yet.
        func executeOnce(block: () -> Void) {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            
            guard !isResumed else { return }
            isResumed = true
            block()
        }
    }

 //AI Suggested fix 4 (Seems to work )
    enum BLEMessageProcessorError: Error {
        case concurrentCommandDetected
        case responseTimeout
    }

    func waitForResponse(timeout: TimeInterval) async throws -> [String] {
        obdDebug(" === Trace === In BLEMessageProcessor func  waitForResponse ")
        // 1. Throw a clean error instead of crashing if a command is active
        guard messageCompletion == nil else {
            throw BLEMessageProcessorError.concurrentCommandDetected
        }
        
        let stateTracker = SafeContinuationState()
        
        // 2. Set up the completion block before entering the async suspension point
        return try await withTimeout(seconds: timeout, timeoutError: BLEMessageProcessorError.responseTimeout) { [self] in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
                
                messageCompletion = { [weak self] response, error in
                    guard let self = self else { return }
                    
                    stateTracker.executeOnce {
                        // Clear the closure immediately upon completion
                        self.messageCompletion = nil
                        
                        if let response = response {
                            obdDebug("messageCompletion response: \(response)", category: .parsing)
                            continuation.resume(returning: response)
                        } else if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: BLEMessageProcessorError.responseTimeout)
                        }
                    }
                }
            }
        }
    }
// AI Info on what the code is doing
//    This Swift code is designed to safely handle asynchronous Bluetooth (BLE) command execution and
//    prevent app crashes caused by simultaneous requests or double-resumed continuations.It provides a thread-safe way
//    to pause execution, wait for a BLE peripheral to send data back, and safely return that data or throw a timeout
//    error.Here is a breakdown of what the code is doing under the hood, split into its two main components.
//    1. SafeContinuationState (The Safeguard)Swift's modern concurrency requires that an async continuation
//    (like CheckedContinuation) must be resumed exactly once. If you resume it twice, or never resume it,
//    your app will crash or leak memory.This class acts as a thread-safe gatekeeper:
//    os_unfair_lock_s: A low-level, high-performance lock that ensures only one thread
//    can modify the state at a time.isResumed: A boolean flag tracking whether the operation
//    has already finished.executeOnce(block:): Locks the thread, checks if isResumed is already true,
//    and if not, flips it to true and runs the provided code. If another thread tries to call this again,
//    the guard statement catches it and returns early, preventing a double-resume crash.
//    2. waitForResponse(timeout:) (The Async Workflow)This function pauses execution until your
//    BLE device responds or times out.Step 1: Concurrency Protectionswiftguard messageCompletion == nil else {
//        throw BLEMessageProcessorError.concurrentCommandDetected
//    }
//    Use code with caution.It checks if a BLE command is already in progress.If messageCompletion
//        is already holding a callback, it throws a clean error instead of letting
//        a second command corrupt your app's state.
//        Step 2: Setting up the BridgeswiftwithCheckedThrowingContinuation { continuation in ... }
//    Use code with caution.This suspends the current function and gives you a continuation object.
//        The code inside this block sets up a callback closure (messageCompletion) that waits
//        for the actual hardware BLE delegate event to fire.Step 3: Thread-Safe ResolutionswiftstateTracker.executeOnce {
//        self.messageCompletion = nil
//        // ... resume continuation with response or error
//    }
//    Use code with caution.When the BLE device finally responds (or a timeout hits),
//        the code calls the messageCompletion block.Inside executeOnce,
//    it immediately clears messageCompletion = nil to free up the class for the next command.
//    It then safely unpacks the BLE response or error and hands it back to the continuation to wake up your async function.
//    Step 4: Wrapping it in a TimeoutswiftwithTimeout(seconds: timeout, ...)
//    Use code with caution.The entire operation is wrapped in a timeout wrapper.
//    If the BLE hardware hangs and never responds, this wrapper triggers,
//    and stateTracker ensures that the late-arriving BLE response doesn't cause a crash later on.
//
//
    
    
 //AI Suggested fix 3
    
//    func waitForResponse(timeout: TimeInterval) async throws -> [String] {
//        // 1. Guard against concurrent commands before changing state
//        assert(messageCompletion == nil, "Concurrent command detected")
//
//        // Ensure we clean up if the outer timeout cancels this block
//        defer {
//            messageCompletion = nil
//        }
//
//        return try await withTimeout(seconds: timeout, timeoutError: BLEMessageProcessorError.responseTimeout) { [self] in
//            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
//                let stateTracker = SafeContinuationState()
//
//                messageCompletion = { [weak self] response, error in
//                    guard let self = self else { return }
//
//                    stateTracker.executeOnce {
//                        // Clean up immediately on success/error path
//                        self.messageCompletion = nil
//
//                        if let response = response {
//                            obdDebug("messageCompletion response: \(response)", category: .parsing)
//                            continuation.resume(returning: response)
//                        } else if let error = error {
//                            continuation.resume(throwing: error)
//                        } else {
//                            continuation.resume(throwing: BLEMessageProcessorError.responseTimeout)
//                        }
//                    }
//                }
//            }
//        }
//    }
    
//AI Suggested fix 2
//    func waitForResponse(timeout: TimeInterval) async throws -> [String] {
//        // 1. Guard against concurrent commands before changing state
//        assert(messageCompletion == nil, "Concurrent command detected")
//
//        return try await withTimeout(seconds: timeout, timeoutError: BLEMessageProcessorError.responseTimeout) { [self] in
//            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
//                // Instantiate the thread-safe tracker for this specific continuation instance
//                let stateTracker = SafeContinuationState()
//
//                messageCompletion = { [weak self] response, error in
//                    guard let self = self else { return }
//
//                    // Use the lock wrapper to guarantee single execution
//                    stateTracker.executeOnce {
//                        // Clean up the completion handler state immediately to unblock future commands
//                        self.messageCompletion = nil
//
//                        if let response = response {
//                            obdDebug("messageCompletion response: \(response)", category: .parsing)
//                            continuation.resume(returning: response)
//                        } else if let error = error {
//                            continuation.resume(throwing: error)
//                        } else {
//                            continuation.resume(throwing: BLEMessageProcessorError.responseTimeout)
//                        }
//                    }
//                }
//            }
//        }
//    }

    
        //AI Suggested fix 1
//    func waitForResponse(timeout: TimeInterval) async throws -> [String] {
//        // 1. Guard against concurrent commands immediately before changing state
//        assert(messageCompletion == nil, "Concurrent command detected")
//
//        return try await withTimeout(seconds: timeout, timeoutError: BLEMessageProcessorError.responseTimeout) { [self] in
//            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
//                // Thread-safe flag to ensure the continuation is only resumed exactly once
//                let isResumed = ManagedAtomic<Bool>(false) // Or a standard lock/unfair_lock wrapper if not using Atomics
//
//                messageCompletion = { [weak self] response, error in
//                    guard let self = self else { return }
//
//                    // Atomically check and set to guarantee single execution
//                    // If you don't use swift-atomics, wrap this block in an os_unfair_lock
//                    if isResumed.compareExchange(expected: false, desired: true, ordering: .sequentiallyConsistent).exchanged {
//                        // Clean up the completion handler state immediately to unblock future commands
//                        self.messageCompletion = nil
//
//                        if let response = response {
//                            obdDebug("messageCompletion response: \(response)", category: .parsing)
//                            continuation.resume(returning: response)
//                        } else if let error = error {
//                            continuation.resume(throwing: error)
//                        } else {
//                            continuation.resume(throwing: BLEMessageProcessorError.responseTimeout)
//                        }
//                    }
//                }
//            }
//        }
//    }

    
   public func reset() {
        obdDebug(" === Trace === In BLEMessageProcessor func  reset ")
        buffer.removeAll()
        let completion = messageCompletion
        messageCompletion = nil

           // Call completion with error if it exists
        completion?(nil, BLEManagerError.peripheralNotConnected)
       }
}

// MARK: - Error Types

enum BLEMessageProcessorError: Error, LocalizedError {
    case characteristicNotWritable
    case writeOperationFailed
    case responseTimeout
    case invalidResponseData

    var errorDescription: String? {
        switch self {
        case .characteristicNotWritable:
            return "BLE characteristic does not support write operations"
        case .writeOperationFailed:
            return "Failed to write data to BLE characteristic"
        case .responseTimeout:
            return "Timeout waiting for BLE response"
        case .invalidResponseData:
            return "Received invalid response data from BLE device"
        }
    }
}

