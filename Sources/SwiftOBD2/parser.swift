//
//  parser.swift
//  SmartOBD2
//
//  Created by kemo konteh on 9/19/23.
//

import Foundation

enum FrameType: UInt8, Codable {
    case singleFrame = 0x00
    case firstFrame = 0x10
    case consecutiveFrame = 0x20
}

public enum ECUID: UInt8, Codable {
    case engine = 0x00
    case transmission = 0x01
    case unknown = 0x02

    public var description: String {
        switch self {
        case .engine:
            return "Engine"
        case .transmission:
            return "Transmission"
        case .unknown:
            return "Unknown"
        }
    }
}

enum TxId: UInt8, Codable {
    case engine = 0x00
    case transmission = 0x01
}

public struct CANParser {
    public let messages: [Message]
    let frames: [Frame]

    public init(_ lines: [String], idBits: Int) throws {
        let obdLines = lines
            .map { $0.replacingOccurrences(of: " ", with: "") }
            .filter(\.isHex)

        frames = try obdLines.compactMap { try Frame(raw: $0, idBits: idBits) }

        let framesByECU = Dictionary(grouping: frames) { $0.txID }

        messages = try framesByECU.values.compactMap { try Message(frames: $0) }
        
    }
}

public struct Message: MessageProtocol {
    var frames: [Frame]
    public var data: Data?

    public var ecu: ECUID {
        frames.first?.txID ?? .unknown
    }

    init(frames: [Frame]) throws {
        obdDebug(" === Trace === In MessageProtocol func  init.frames ")
        self.frames = frames
        obdDebug("In init frames \(frames ) and count \(frames.count)")
        
        
        var frameCount = frames.count //sr
        var frameType = frames.first?.type
        
        
 
 //sr
        if frameCount == 2 && frameType == .singleFrame {
            frameCount = 1
        }
 //sr
        obdDebug("Still in init frames type \(String(describing: frameType) ) and count \(frameCount)")
        
//sr        switch frames.count {
        
        switch frameCount  {
        case 1:
                obdDebug("In init frames case 1  \(frames ) and count \(frames.count)")
            data = try parseSingleFrameMessage(frames)
        case 2...:
                obdDebug("In init frames case 2  \(frames ) and count \(frames.count)")
            data = try parseMultiFrameMessage(frames)
        default:
                obdDebug("In init frames case default  \(frames ) and count \(frames.count)")
            data = try parseSingleFrameMessage(frames) //sr
  //sr          throw ParserError.error("Invalid frame count")
        }
    }
    
    
    func debugLog( message: String) -> Bool {
        obdDebug("🔍 [GUARD CHECK] \(message):")
        return true
    }
    
    
    private func parseSingleFrameMessage(_ frames: [Frame]) throws -> Data {
        guard let frame = frames.first, frame.type == .singleFrame,
              let dataLen = frame.dataLen, dataLen > 0,
              frame.data.count >= dataLen + 1
            else { // Pre-validate the length
            throw ParserError.error("Frame validation failed")
        }
        obdDebug("\n Parsing Single Frame: Framedata \(frame)  FrameType: \(frame.type)  Frame.data.count: \(frame.data.count) ")
        let framedatatoreturn = frame.data.dropFirst(2)
        obdDebug("\n Parsing Single Frame return: Framedata \(framedatatoreturn) ,...")
        return frame.data.dropFirst(1)
        return frame.data
    }


    
    
    private func parseMultiFrameMessage(_ frames: [Frame]) throws -> Data {
        guard let firstFrame = frames.first(where: { $0.type == .firstFrame }),
                debugLog(message: "Parsing Multi Frame: \(firstFrame)  ...")
                else {
            throw ParserError.error("Failed to parse multi frame message")
        }
        let consecutiveFrames = frames.filter { $0.type == .consecutiveFrame }
        return try assembleData(firstFrame: firstFrame, consecutiveFrames: consecutiveFrames)
    }

    private func assembleData(firstFrame: Frame, consecutiveFrames: [Frame]) throws -> Data {
        var assembledFrame: Frame = firstFrame
        // Extract data from consecutive frames, skipping the PCI byte
        for frame in consecutiveFrames {
            assembledFrame.data.append(frame.data[1...])
        }
        return try extractDataFromFrame(assembledFrame, startIndex: 3)
    }

    private func extractDataFromFrame(_ frame: Frame, startIndex: Int) throws -> Data {
        guard let frameDataLen = frame.dataLen else {
            throw ParserError.error("Failed to extract data from frame")
        }
        let endIndex = startIndex + Int(frameDataLen) - 1
        guard endIndex <= frame.data.count else {
            return frame.data[startIndex...]
        }
        return frame.data[startIndex ..< endIndex]
    }
}

struct Frame {
    var raw: String
    var data = Data()
    var priority: UInt8
    var addrMode: UInt8
    var rxID: UInt8
    var txID: ECUID
    var type: FrameType
    var seqIndex: UInt8 = 0 // Only used when type = CF
    var dataLen: UInt8?

    init(raw: String, idBits: Int) throws {
        self.raw = raw

      let paddedRawData = idBits == 11 ? "00000" + raw : raw

        let dataBytes = paddedRawData.hexBytes

        data = Data(dataBytes.dropFirst(4))
        
        obdDebug("Raw data Display : \(raw)", category: .parsing)
        obdDebug("Padded raw data Display : \(paddedRawData)", category: .parsing)
        obdDebug("dataBytes Display : \(dataBytes)", category: .parsing)
        let datalen  = data.count
        obdDebug("data after drop 4  : \(data)  ")
        dump(dataBytes)

        guard dataBytes.count >= 6, dataBytes.count <= 12 else {
            obdError("Invalid frame size: \(dataBytes.count) bytes", category: .parsing)
            OBDLogger.shared.logParseError("Frame size out of range (6-12 bytes)", data: Data(dataBytes), expectedFormat: "6-12 bytes")
            throw ParserError.error("Invalid frame size")
            
// sr       guard data.count >= 6, data.count <= 12 else {
// sr           obdError("Invalid frame size: \(data.count) bytes", category: .parsing)
// sr           OBDLogger.shared.logParseError("Frame size out of range (6-12 bytes)", data: Data(data), expectedFormat: "6-12 bytes")
// sr           throw ParserError.error("Invalid frame size")
        }

        
        guard let dataType = data.first,
              let type = FrameType(rawValue: dataType & 0xF0)
        else {
// sr           obdError("Invalid frame type detected", category: .parsing)
//  sr          obdError("data type in error: \(data.first)", category: .parsing)
//  sr          OBDLogger.shared.logParseError("Unknown frame type",  data: Data(data), expectedFormat: "Valid FrameType enum value")
//  sr          OBDLogger.shared.logParseError("Unknown frame type", data: Data(dataBytes), expectedFormat: "Valid FrameType enum value")
// sr           throw ParserError.error("Invalid frame type")
            obdError("Invalid frame type detected", category: .parsing)
            OBDLogger.shared.logParseError("Unknown frame type", data: Data(dataBytes), expectedFormat: "Valid FrameType enum value")
            throw ParserError.error("Invalid frame type")
        }

        priority = dataBytes[2] & 0x0F
        addrMode = dataBytes[3] & 0xF0
        rxID = dataBytes[2]
        txID = ECUID(rawValue: dataBytes[3] & 0x07) ?? .unknown
        self.type = type
   
        obdDebug("Frame type indicated as : \(type)", category: .parsing)
        
        switch type {
        case .singleFrame:
            dataLen = (data[0] & 0x0F)
            obdDebug("Case singleFrame Datalen value : \(dataLen)", category: .parsing)
        case .firstFrame:
            dataLen = ((UInt8(data[0] & 0x0F) << 8) + UInt8(data[1]))
        case .consecutiveFrame:
            seqIndex = data[0] & 0x0F
        }
    }
}

enum ParserError: Error {
    case error(String)
}

