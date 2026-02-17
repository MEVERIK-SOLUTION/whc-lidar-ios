//
//  ContentView.swift
//  whc-lidar-ios
//
//  Created by Matěj Kocanda on 16.02.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var isPresentingScanner = false
    @State private var jsonExportURL: URL?
    @State private var usdzExportURL: URL?
    @State private var svgExportURL: URL?
    @State private var errorMessage: String?
    @State private var isPresentingPreview = false
    @State private var roomName = ""
    @State private var roomType = ""
    @State private var userId = ""
    @State private var scanId = UUID().uuidString
    @StateObject private var uploadManager = RoomUploadManager()

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var body: some View {
        VStack(spacing: 16) {
            Text("RoomPlan Scanner")
                .font(.title2)
                .fontWeight(.semibold)

            Button("Start Room Scan") {
                errorMessage = nil
                isPresentingScanner = true
            }
            .buttonStyle(.borderedProminent)

            #if targetEnvironment(simulator)
            Button("Mock Scan (Simulator)") {
                errorMessage = nil
                do {
                    let mockURLs = try createMockScanFiles()
                    jsonExportURL = mockURLs.json
                    usdzExportURL = mockURLs.usdz
                    svgExportURL = mockURLs.svg
                    scanId = "test-sim-001"
                    roomName = "Living Room"
                    roomType = "living_room"
                    userId = "user-sim-001"
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .buttonStyle(.bordered)
            #endif

            if let jsonExportURL, let usdzExportURL, let svgExportURL {
                VStack(spacing: 12) {
                    Text("Export Options")
                        .font(.headline)

                    TextField("Room name", text: $roomName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Room type", text: $roomType)
                        .textFieldStyle(.roundedBorder)
                    TextField("User ID", text: $userId)
                        .textFieldStyle(.roundedBorder)

                    ShareLink("Share JSON", item: jsonExportURL)
                    ShareLink("Share USDZ", item: usdzExportURL)
                    ShareLink("Share SVG", item: svgExportURL)

                    Button("Preview USDZ") {
                        isPresentingPreview = true
                    }
                    .buttonStyle(.bordered)

                    Button("Upload to Server") {
                        let metadata = RoomUploadMetadata(
                            scanId: scanId,
                            roomName: roomName.isEmpty ? "Untitled" : roomName,
                            roomType: roomType.isEmpty ? "unknown" : roomType,
                            length: extractDimension(from: jsonExportURL, key: "length"),
                            width: extractDimension(from: jsonExportURL, key: "width"),
                            height: extractDimension(from: jsonExportURL, key: "height"),
                            scanDateISO8601: isoFormatter.string(from: Date()),
                            deviceModel: UIDevice.current.model,
                            userId: userId.isEmpty ? "unknown" : userId
                        )
                        uploadManager.upload(
                            metadata: metadata,
                            jsonURL: jsonExportURL,
                            usdzURL: usdzExportURL,
                            svgURL: svgExportURL
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(uploadManager.isUploading)

                    if uploadManager.isUploading {
                        ProgressView(value: uploadManager.progress)
                    }

                    if let statusMessage = uploadManager.statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .sheet(isPresented: $isPresentingScanner) {
            if #available(iOS 16.0, *) {
                RoomScannerView(
                    onFinish: { jsonURL, usdzURL, svgURL in
                        jsonExportURL = jsonURL
                        usdzExportURL = usdzURL
                        svgExportURL = svgURL
                        scanId = UUID().uuidString
                        isPresentingScanner = false
                    },
                    onCancel: {
                        isPresentingScanner = false
                    },
                    onError: { error in
                        errorMessage = error.localizedDescription
                        isPresentingScanner = false
                    }
                )
            } else {
                Text("RoomPlan requires iOS 16 or later.")
            }
        }
        .sheet(isPresented: $isPresentingPreview) {
            if let usdzExportURL {
                USDZPreviewView(fileURL: usdzExportURL)
            } else {
                Text("No USDZ available.")
            }
        }
    }

    private func extractDimension(from jsonURL: URL, key: String) -> Float {
        guard let data = try? Data(contentsOf: jsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dimensions = json["dimensions"] as? [String: Any],
              let value = dimensions[key] as? NSNumber else {
            return 0
        }
        return value.floatValue
    }

    private func createMockScanFiles() throws -> (json: URL, usdz: URL, svg: URL) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent("MockScans", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970)
        let jsonURL = folder.appendingPathComponent("mock-\(timestamp).json")
        let usdzURL = folder.appendingPathComponent("mock-\(timestamp).usdz")
        let svgURL = folder.appendingPathComponent("mock-\(timestamp).svg")

        let jsonString = """
        {
          \"dimensions\": {\"length\": 5.5, \"width\": 4.2, \"height\": 2.8},
          \"furniture\": [
            {\"type\": \"sofa\", \"position\": [1.2, 0.0, 2.0]},
            {\"type\": \"table\", \"position\": [2.4, 0.0, 1.1]}
          ]
        }
        """
        try jsonString.write(to: jsonURL, atomically: true, encoding: .utf8)

        let svgString = """
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"320\" height=\"240\" viewBox=\"0 0 320 240\">
          <rect x=\"20\" y=\"20\" width=\"280\" height=\"200\" fill=\"none\" stroke=\"#111827\" stroke-width=\"2\"/>
          <circle cx=\"120\" cy=\"120\" r=\"6\" fill=\"#2563eb\"/>
          <circle cx=\"200\" cy=\"80\" r=\"6\" fill=\"#2563eb\"/>
        </svg>
        """
        try svgString.write(to: svgURL, atomically: true, encoding: .utf8)

        let usdzData = Data("USDZ_PLACEHOLDER".utf8)
        try usdzData.write(to: usdzURL, options: [.atomic])

        return (json: jsonURL, usdz: usdzURL, svg: svgURL)
    }
}

#Preview {
    ContentView()
}
