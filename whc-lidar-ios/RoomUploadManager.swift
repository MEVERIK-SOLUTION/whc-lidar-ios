//
//  RoomUploadManager.swift
//  whc-lidar-ios
//
//  Created by Matěj Kocanda on 16.02.2026.
//

import Foundation
import Combine
import UIKit

struct RoomUploadMetadata {
    let scanId: String
    let roomName: String
    let roomType: String
    let length: Float
    let width: Float
    let height: Float
    let scanDateISO8601: String
    let deviceModel: String
    let userId: String
}

struct BackendScan: Decodable {
    let id: String?
    let usdzURL: String?
    let floorplanSVGURL: String?
    let jsonURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case usdzURL = "usdz_url"
        case floorplanSVGURL = "floorplan_svg_url"
        case jsonURL = "json_url"
    }
}

struct BackendUploadResponse: Decodable {
    let scan: BackendScan?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try container.decodeIfPresent(BackendScan.self, forKey: .scan) {
            scan = nested
            return
        }
        scan = try BackendScan(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case scan
    }
}

enum RoomUploadError: LocalizedError {
    case invalidResponse
    case badStatus(Int, String)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Upload failed: No response."
        case .badStatus(let code, let message):
            return "Upload failed (\(code)) \(message)"
        case .decodeFailed:
            return "Upload failed: Invalid response JSON."
        }
    }
}

final class RoomUploadManager: NSObject, ObservableObject {
    @Published var progress: Double = 0
    @Published var isUploading = false
    @Published var statusMessage: String?
    @Published var lastResponse: BackendUploadResponse?

    private var session: URLSession?

    func upload(
        metadata: RoomUploadMetadata,
        jsonURL: URL,
        usdzURL: URL,
        svgURL: URL,
        endpoint: URL = URL(string: "http://127.0.0.1:8000/upload")!,
        completion: ((Result<BackendUploadResponse, Error>) -> Void)? = nil
    ) {
        guard !isUploading else { return }

        isUploading = true
        progress = 0
        statusMessage = nil
        lastResponse = nil

        do {
            let jsonData = try Data(contentsOf: jsonURL)
            let usdzData = try Data(contentsOf: usdzURL)
            let svgData = try Data(contentsOf: svgURL)

            print("[Upload] Starting backend upload")
            print("[Upload] scan_id=\(metadata.scanId) room_name=\(metadata.roomName) room_type=\(metadata.roomType)")
            print("[Upload] dimensions=\(fmt(metadata.length))x\(fmt(metadata.width))x\(fmt(metadata.height))")
            print("[Upload] scan_date=\(metadata.scanDateISO8601) device=\(metadata.deviceModel) user_id=\(metadata.userId)")
            print("[Upload] files json=\(jsonData.count)B usdz=\(usdzData.count)B svg=\(svgData.count)B")

            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            let body = makeMultipartBody(
                boundary: boundary,
                metadata: metadata,
                jsonData: jsonData,
                jsonFilename: jsonURL.lastPathComponent,
                usdzData: usdzData,
                usdzFilename: usdzURL.lastPathComponent,
                svgData: svgData,
                svgFilename: svgURL.lastPathComponent
            )

            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session

            let task = session.uploadTask(with: request, from: body) { [weak self] data, response, error in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isUploading = false

                    if let error {
                        print("[Upload] Error: \(error.localizedDescription)")
                        print("[Upload] Error detail: \(String(describing: error))")
                        self.statusMessage = "Upload failed: \(error.localizedDescription)"
                        completion?(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("[Upload] Error: No HTTP response")
                        let err = RoomUploadError.invalidResponse
                        self.statusMessage = err.localizedDescription
                        completion?(.failure(err))
                        return
                    }

                    print("[Upload] HTTP status: \(httpResponse.statusCode)")
                    if let data {
                        print(self.formatJSONLog(data))
                    } else {
                        print("[Upload] Response: <empty>")
                    }

                    if (200...299).contains(httpResponse.statusCode) {
                        let responseData = data ?? Data()
                        let decoder = JSONDecoder()
                        if let decoded = try? decoder.decode(BackendUploadResponse.self, from: responseData) {
                            self.statusMessage = "Upload succeeded."
                            self.lastResponse = decoded
                            if let scan = decoded.scan {
                                print("[Upload] Parsed scan.id=\(scan.id ?? "")")
                                print("[Upload] Parsed usdz_url=\(scan.usdzURL ?? "")")
                                print("[Upload] Parsed floorplan_svg_url=\(scan.floorplanSVGURL ?? "")")
                                print("[Upload] Parsed json_url=\(scan.jsonURL ?? "")")
                            } else {
                                print("[Upload] Parsed scan: <nil>")
                            }
                            completion?(.success(decoded))
                        } else {
                            print("[Upload] Error: Failed to decode JSON response")
                            let err = RoomUploadError.decodeFailed
                            self.statusMessage = err.localizedDescription
                            completion?(.failure(err))
                        }
                    } else {
                        let serverMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        print("[Upload] Error: HTTP \(httpResponse.statusCode) \(serverMessage)")
                        let err = RoomUploadError.badStatus(httpResponse.statusCode, serverMessage)
                        self.statusMessage = err.localizedDescription
                        completion?(.failure(err))
                    }
                }
            }

            task.resume()
        } catch {
            print("[Upload] Error: \(error.localizedDescription)")
            print("[Upload] Error detail: \(String(describing: error))")
            isUploading = false
            statusMessage = "Upload failed: \(error.localizedDescription)"
            completion?(.failure(error))
        }
    }

    private func makeMultipartBody(
        boundary: String,
        metadata: RoomUploadMetadata,
        jsonData: Data,
        jsonFilename: String,
        usdzData: Data,
        usdzFilename: String,
        svgData: Data,
        svgFilename: String
    ) -> Data {
        var body = Data()

        body.append(textField(name: "scan_id", value: metadata.scanId, boundary: boundary))
        body.append(textField(name: "room_name", value: metadata.roomName, boundary: boundary))
        body.append(textField(name: "room_type", value: metadata.roomType, boundary: boundary))
        body.append(textField(name: "length", value: fmt(metadata.length), boundary: boundary))
        body.append(textField(name: "width", value: fmt(metadata.width), boundary: boundary))
        body.append(textField(name: "height", value: fmt(metadata.height), boundary: boundary))
        body.append(textField(name: "scan_date", value: metadata.scanDateISO8601, boundary: boundary))
        body.append(textField(name: "device_model", value: metadata.deviceModel, boundary: boundary))
        body.append(textField(name: "user_id", value: metadata.userId, boundary: boundary))

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"scan_json\"; filename=\"\(jsonFilename)\"\r\n")
        body.append("Content-Type: application/json\r\n\r\n")
        body.append(jsonData)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"usdz_file\"; filename=\"\(usdzFilename)\"\r\n")
        body.append("Content-Type: model/vnd.usdz+zip\r\n\r\n")
        body.append(usdzData)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"floorplan_svg\"; filename=\"\(svgFilename)\"\r\n")
        body.append("Content-Type: image/svg+xml\r\n\r\n")
        body.append(svgData)
        body.append("\r\n")

        body.append("--\(boundary)--\r\n")

        return body
    }

    private func textField(name: String, value: String, boundary: String) -> Data {
        var field = Data()
        field.append("--\(boundary)\r\n")
        field.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        field.append(value)
        field.append("\r\n")
        return field
    }

    private func fmt(_ value: Float) -> String {
        String(format: "%.4f", value)
    }

    private func formatJSONLog(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
           let prettyString = String(data: pretty, encoding: .utf8) {
            return "[Upload] Response JSON:\n\(prettyString)"
        }
        if let raw = String(data: data, encoding: .utf8) {
            return "[Upload] Response (raw):\n\(raw)"
        }
        return "[Upload] Response: <non-text data>"
    }
}

extension RoomUploadManager: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let newProgress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async { [weak self] in
            self?.progress = newProgress
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
