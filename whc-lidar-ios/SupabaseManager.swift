//
//  SupabaseManager.swift
//  whc-lidar-ios
//
//  Created by Matěj Kocanda on 16.02.2026.
//

import Foundation
import Supabase

struct ScanUploadMetadata {
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

struct ScanUploadResult {
    let usdzURL: String
    let svgURL: String
    let jsonURL: String
}

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://jtcqmdmxqsnkiwimujaz.supabase.co")!,
            supabaseKey: "sb_publishable_FRB5K9ByebOjlZhGl70reg_kuQsjny7"
        )
    }

    func uploadScan(
        metadata: ScanUploadMetadata,
        jsonURL: URL,
        usdzURL: URL,
        svgURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> ScanUploadResult {
        progress(0.05)

        let storage = client.storage.from("scans")
        let jsonData = try Data(contentsOf: jsonURL)
        let usdzData = try Data(contentsOf: usdzURL)
        let svgData = try Data(contentsOf: svgURL)

        let usdzPath = "\(metadata.scanId)/model.usdz"
        let svgPath = "\(metadata.scanId)/floorplan.svg"
        let jsonPath = "\(metadata.scanId)/metadata.json"

        try await storage.upload(
            usdzPath,
            data: usdzData,
            options: FileOptions(contentType: "model/vnd.usdz+zip", upsert: true)
        )
        progress(0.40)

        try await storage.upload(
            svgPath,
            data: svgData,
            options: FileOptions(contentType: "image/svg+xml", upsert: true)
        )
        progress(0.65)

        try await storage.upload(
            jsonPath,
            data: jsonData,
            options: FileOptions(contentType: "application/json", upsert: true)
        )
        progress(0.80)

        let usdzPublicURL = try storage.getPublicURL(path: usdzPath).absoluteString
        let svgPublicURL = try storage.getPublicURL(path: svgPath).absoluteString
        let jsonPublicURL = try storage.getPublicURL(path: jsonPath).absoluteString

        let insert = ScanInsert(
            scanId: metadata.scanId,
            roomName: metadata.roomName,
            roomType: metadata.roomType,
            length: metadata.length,
            width: metadata.width,
            height: metadata.height,
            usdzURL: usdzPublicURL,
            floorplanSVGURL: svgPublicURL,
            jsonURL: jsonPublicURL,
            scanDate: metadata.scanDateISO8601,
            deviceModel: metadata.deviceModel,
            userId: metadata.userId
        )

        _ = try await client
            .from("scans")
            .insert(insert)
            .execute()

        progress(1.0)

        return ScanUploadResult(
            usdzURL: usdzPublicURL,
            svgURL: svgPublicURL,
            jsonURL: jsonPublicURL
        )
    }
}

private struct ScanInsert: Encodable {
    let scanId: String
    let roomName: String
    let roomType: String
    let length: Float
    let width: Float
    let height: Float
    let usdzURL: String
    let floorplanSVGURL: String
    let jsonURL: String
    let scanDate: String
    let deviceModel: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case scanId = "scan_id"
        case roomName = "room_name"
        case roomType = "room_type"
        case length
        case width
        case height
        case usdzURL = "usdz_url"
        case floorplanSVGURL = "floorplan_svg_url"
        case jsonURL = "json_url"
        case scanDate = "scan_date"
        case deviceModel = "device_model"
        case userId = "user_id"
    }
}
