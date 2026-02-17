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

    @State private var isLoading = false
    @State private var uploadResult: UploadResponse?

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var body: some View {
        VStack(spacing: 16) {
            Text("Skener místností")
                .font(.title2)
                .fontWeight(.semibold)

            Button("Začít skenování") {
                errorMessage = nil
                isPresentingScanner = true
            }
            .buttonStyle(.borderedProminent)

            #if targetEnvironment(simulator)
            Button("Testovací sken (Simulátor)") {
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

            Button {
                Task { await uploadDummyScan() }
            } label: {
                Text(isLoading ? "Uploading…" : "Upload Scan")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            if let uploadResult {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Upload OK")
                        .font(.headline)
                    Text("id: \(uploadResult.id)")
                    Text("scan_id: \(uploadResult.scan_id)")
                    if let modelURL = uploadResult.model_url {
                        Text("model_url: \(modelURL)")
                    }
                    if let floorplanURL = uploadResult.scan.floorplan_url {
                        Text("floorplan_url: \(floorplanURL)")
                    }
                    if let jsonURL = uploadResult.scan.json_url {
                        Text("json_url: \(jsonURL)")
                    }
                }
                .textSelection(.enabled)
            }

            if let jsonExportURL, let usdzExportURL, let svgExportURL {
                VStack(spacing: 12) {
                    Text("Možnosti exportu")
                        .font(.headline)

                    TextField("Název místnosti", text: $roomName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Typ místnosti", text: $roomType)
                        .textFieldStyle(.roundedBorder)
                    TextField("ID uživatele", text: $userId)
                        .textFieldStyle(.roundedBorder)

                    ShareLink("Sdílet JSON", item: jsonExportURL)
                    ShareLink("Sdílet USDZ", item: usdzExportURL)
                    ShareLink("Sdílet SVG", item: svgExportURL)

                    Button("Náhled USDZ") {
                        isPresentingPreview = true
                    }
                    .buttonStyle(.bordered)

                    Button("Nahrát na server") {
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
                Text("RoomPlan vyžaduje iOS 16 nebo novější.")
            }
        }
        .sheet(isPresented: $isPresentingPreview) {
            if let usdzExportURL {
                USDZPreviewView(fileURL: usdzExportURL)
            } else {
                Text("USDZ není k dispozici.")
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

    private func uploadDummyScan() async {
        isLoading = true
        errorMessage = nil
        uploadResult = nil

        // Dummy data for testing networking + backend integration.
        // Backend only checks extension and non-empty content.
        let dummyUSDZ = Data([0x55, 0x53, 0x44, 0x5A]) // "USDZ" bytes (not a real USDZ)
        let dummySVG = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"></svg>".utf8)
        let metadataJSON = "{}"

        do {
            let response = try await APIClient.shared.uploadScan(
                modelFile: dummyUSDZ,
                floorplanFile: dummySVG,
                metadataJSON: metadataJSON
            )
            uploadResult = response
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    ContentView()
}
