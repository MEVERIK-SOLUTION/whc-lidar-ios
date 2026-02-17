import Foundation
import UIKit

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://whc-li-dar-app-backend.vercel.app")!

    enum APIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int, body: String)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .invalidResponse:
                return "Invalid response"
            case .httpError(let statusCode, let body):
                return "HTTP \(statusCode): \(body)"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            }
        }
    }

    /// Uploads a scan to backend `/upload`.
    ///
    /// Note: backend currently expects `usdz_file`, `floorplan_svg` (required there), and `scan_json`.
    /// This client also sends `file_type` and `metadata` fields (ignored by backend if unused).
    func uploadScan(modelFile: Data, floorplanFile: Data?, metadataJSON: String) async throws -> UploadResponse {
        let url = baseURL.appendingPathComponent("upload")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let scanId = "ios-\(UUID().uuidString)"
        let deviceModel = UIDevice.current.model
        let nowISO = ISO8601DateFormatter().string(from: Date())

        var body = Data()

        // Form fields expected by backend schema (only required ones here).
        body.appendMultipartField(name: "scan_id", value: scanId, boundary: boundary)
        body.appendMultipartField(name: "room_name", value: "iOS Upload", boundary: boundary)
        body.appendMultipartField(name: "room_type", value: "unknown", boundary: boundary)
        body.appendMultipartField(name: "scan_date", value: nowISO, boundary: boundary)
        body.appendMultipartField(name: "device_model", value: deviceModel, boundary: boundary)
        body.appendMultipartField(name: "user_id", value: "ios", boundary: boundary)

        // Fields requested in the task (safe extras for backend).
        body.appendMultipartField(name: "file_type", value: "model", boundary: boundary)
        body.appendMultipartField(name: "metadata", value: metadataJSON, boundary: boundary)

        // Files.
        body.appendMultipartFile(name: "usdz_file", filename: "model.usdz", mimeType: "model/vnd.usdz+zip", fileData: modelFile, boundary: boundary)

        if let floorplanFile {
            // Backend expects `floorplan_svg`. Task text mentions `floorplan_file` — we can send both.
            body.appendMultipartFile(name: "floorplan_svg", filename: "floorplan.svg", mimeType: "image/svg+xml", fileData: floorplanFile, boundary: boundary)
            body.appendMultipartFile(name: "floorplan_file", filename: "floorplan.svg", mimeType: "image/svg+xml", fileData: floorplanFile, boundary: boundary)
        }

        let jsonData = Data(metadataJSON.utf8)
        body.appendMultipartFile(name: "scan_json", filename: "metadata.json", mimeType: "application/json", fileData: jsonData, boundary: boundary)

        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
            throw APIError.httpError(statusCode: http.statusCode, body: bodyText)
        }

        do {
            return try JSONDecoder().decode(UploadResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, fileData: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}
