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

