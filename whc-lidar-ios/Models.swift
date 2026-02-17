import Foundation

// Matches current backend response shape:
// {
//   "scan": { "id": "...", "scan_id": "...", "model_url": "...", ... },
//   "files": { "model": {"path": "...", "public_url": "..."}, ... }
// }
struct UploadResponse: Codable {
    let scan: Scan
    let files: UploadedFiles

    var id: String { scan.id }
    var scan_id: String { scan.scan_id }
    var model_url: String? { scan.model_url ?? files.model.public_url }

    struct Scan: Codable {
        let id: String
        let scan_id: String
        let room_name: String?
        let room_type: String?
        let length: Double?
        let width: Double?
        let height: Double?
        let scan_date: String?
        let device_model: String?
        let user_id: String?
        let model_url: String?
        let floorplan_url: String?
        let json_url: String?
        let created_at: String?
        let updated_at: String?
    }

    struct UploadedFiles: Codable {
        let model: FileInfo
        let floorplan: FileInfo?
        let json: FileInfo

        struct FileInfo: Codable {
            let path: String
            let public_url: String
        }
    }
}

struct ScanFile: Identifiable {
    let id: UUID
    let name: String
    let data: Data

    init(id: UUID = UUID(), name: String, data: Data) {
        self.id = id
        self.name = name
        self.data = data
    }
}
