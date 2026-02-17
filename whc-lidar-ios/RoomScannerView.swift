//
//  RoomScannerView.swift
//  whc-lidar-ios
//
//  Created by Matěj Kocanda on 16.02.2026.
//

import RoomPlan
import SwiftUI
import UIKit
import simd
import Combine

private struct RoomExport: Codable {
    let dimensions: RoomDimensions
    let furniture: [FurnitureItem]
}

private struct RoomDimensions: Codable {
    let length: Float
    let width: Float
    let height: Float
}

private struct FurnitureItem: Codable {
    let type: String
    let position: [Float]
}

@available(iOS 16.0, *)
final class RoomPlanViewController: UIViewController, RoomCaptureSessionDelegate {
    var onFinish: ((CapturedRoom) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let captureView = RoomCaptureView(frame: .zero)
    private let sessionConfig = RoomCaptureSession.Configuration()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        captureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureView)

        NSLayoutConstraint.activate([
            captureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            captureView.topAnchor.constraint(equalTo: view.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        captureView.captureSession.delegate = self

        navigationItem.title = "Room Scan"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Finish",
            style: .prominent,
            target: self,
            action: #selector(finishTapped)
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureView.captureSession.run(configuration: sessionConfig)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureView.captureSession.stop()
    }

    @objc private func cancelTapped() {
        captureView.captureSession.stop()
        onCancel?()
    }

    @objc private func finishTapped() {
        captureView.captureSession.stop()
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith capturedRoom: CapturedRoom, error: Error?) {
        if let error {
            onError?(error)
            return
        }
        onFinish?(capturedRoom)
    }
}

@available(iOS 16.0, *)
final class RoomScannerViewController: UIViewController {
    var onFinish: ((URL, URL, URL) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let roomPlanViewController = RoomPlanViewController()
    private let uploadStatusLabel = UILabel()
    private let uploadProgressView = UIProgressView(progressViewStyle: .default)
    private let uploadContainer = UIStackView()
    private let backendUploadManager = RoomUploadManager()
    private var uploadCancellables = Set<AnyCancellable>()
    private var lastExportURLs: (json: URL, usdz: URL, svg: URL)?
    private var lastStatusMessage: String?
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(roomPlanViewController)
        roomPlanViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(roomPlanViewController.view)
        NSLayoutConstraint.activate([
            roomPlanViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            roomPlanViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            roomPlanViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            roomPlanViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        roomPlanViewController.didMove(toParent: self)

        setupUploadUI()
        bindUploadManager()

        roomPlanViewController.onFinish = { [weak self] capturedRoom in
            self?.exportCapturedRoom(capturedRoom)
        }
        roomPlanViewController.onCancel = { [weak self] in
            self?.onCancel?()
        }
        roomPlanViewController.onError = { [weak self] error in
            self?.onError?(error)
        }
    }

    private func exportCapturedRoom(_ capturedRoom: CapturedRoom) {
        do {
            let exportFolder = try makeExportFolder()
            let jsonURL = exportFolder.appendingPathComponent("room.json")
            let usdzURL = exportFolder.appendingPathComponent("room.usdz")
            let svgURL = exportFolder.appendingPathComponent("room.svg")

            let bounds = makeRoomBounds(from: capturedRoom)
            let wallSegments = makeWallSegments(from: capturedRoom)
            let doorSegments = makeDoorSegments(from: capturedRoom)
            let export = makeRoomExport(from: capturedRoom, bounds: bounds)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(export)
            try jsonData.write(to: jsonURL, options: [.atomic])

            let svg = makeSVG(
                from: export,
                bounds: bounds,
                wallSegments: wallSegments,
                doorSegments: doorSegments
            )
            try svg.write(to: svgURL, atomically: true, encoding: .utf8)

            try capturedRoom.export(to: usdzURL, exportOptions: .parametric)

            DispatchQueue.main.async { [weak self] in
                self?.presentMetadataPrompt(
                    jsonURL: jsonURL,
                    usdzURL: usdzURL,
                    svgURL: svgURL,
                    dimensions: export.dimensions
                )
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(error)
            }
        }
    }

    private func presentMetadataPrompt(
        jsonURL: URL,
        usdzURL: URL,
        svgURL: URL,
        dimensions: RoomDimensions
    ) {
        let alert = UIAlertController(title: "Upload Scan", message: "Enter room info", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Room name" }
        alert.addTextField { $0.placeholder = "Room type" }
        alert.addTextField { field in
            field.placeholder = "Length (m)"
            field.keyboardType = .decimalPad
            field.text = String(format: "%.2f", dimensions.length)
        }
        alert.addTextField { field in
            field.placeholder = "Width (m)"
            field.keyboardType = .decimalPad
            field.text = String(format: "%.2f", dimensions.width)
        }
        alert.addTextField { field in
            field.placeholder = "Height (m)"
            field.keyboardType = .decimalPad
            field.text = String(format: "%.2f", dimensions.height)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Upload", style: .default) { [weak self] _ in
            guard let self else { return }
            let scanId = UUID().uuidString

            let roomName = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let roomType = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let length = Float(alert.textFields?[2].text ?? "") ?? dimensions.length
            let width = Float(alert.textFields?[3].text ?? "") ?? dimensions.width
            let height = Float(alert.textFields?[4].text ?? "") ?? dimensions.height

            let metadata = RoomUploadMetadata(
                scanId: scanId,
                roomName: roomName.isEmpty ? "Untitled" : roomName,
                roomType: roomType.isEmpty ? "unknown" : roomType,
                length: length,
                width: width,
                height: height,
                scanDateISO8601: self.isoFormatter.string(from: Date()),
                deviceModel: UIDevice.current.model,
                userId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            )

            self.startUpload(
                metadata: metadata,
                jsonURL: jsonURL,
                usdzURL: usdzURL,
                svgURL: svgURL
            )
        })

        present(alert, animated: true)
    }

    private func startUpload(metadata: RoomUploadMetadata, jsonURL: URL, usdzURL: URL, svgURL: URL) {
        lastExportURLs = (json: jsonURL, usdz: usdzURL, svg: svgURL)
        showUploadProgress(message: "Uploading to backend…", progress: 0)
        backendUploadManager.upload(metadata: metadata, jsonURL: jsonURL, usdzURL: usdzURL, svgURL: svgURL)
    }

    private func bindUploadManager() {
        backendUploadManager.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.updateUploadProgress(value)
            }
            .store(in: &uploadCancellables)

        backendUploadManager.$statusMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                self.lastStatusMessage = message
                self.uploadContainer.isHidden = false
                self.uploadStatusLabel.text = message
                let lowercased = message.lowercased()
                if lowercased.contains("succeeded") {
                    if let urls = self.lastExportURLs {
                        self.onFinish?(urls.json, urls.usdz, urls.svg)
                    }
                }
            }
            .store(in: &uploadCancellables)

        backendUploadManager.$lastResponse
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                guard let self else { return }
                let detail = self.formatUploadDetail(response)
                if let status = self.lastStatusMessage, !status.isEmpty {
                    self.uploadStatusLabel.text = status + "\n" + detail
                } else {
                    self.uploadStatusLabel.text = detail
                }
                self.uploadContainer.isHidden = false
                self.updateUploadProgress(1.0)
            }
            .store(in: &uploadCancellables)
    }

    private func formatUploadDetail(_ response: BackendUploadResponse) -> String {
        guard let scan = response.scan else {
            return "No scan details in response."
        }
        var lines: [String] = []
        if let id = scan.id, !id.isEmpty {
            lines.append("Scan ID: \(id)")
        }
        if let usdz = scan.usdzURL, !usdz.isEmpty {
            lines.append("USDZ URL: \(usdz)")
        }
        if let svg = scan.floorplanSVGURL, !svg.isEmpty {
            lines.append("SVG URL: \(svg)")
        }
        if let json = scan.jsonURL, !json.isEmpty {
            lines.append("JSON URL: \(json)")
        }
        if lines.isEmpty {
            return "No URLs returned by backend."
        }
        return lines.joined(separator: "\n")
    }

    private func setupUploadUI() {
        uploadContainer.axis = .vertical
        uploadContainer.alignment = .fill
        uploadContainer.distribution = .fill
        uploadContainer.spacing = 8
        uploadContainer.translatesAutoresizingMaskIntoConstraints = false
        uploadContainer.isHidden = true

        uploadStatusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        uploadStatusLabel.textAlignment = .center
        uploadStatusLabel.numberOfLines = 0

        uploadProgressView.progress = 0

        uploadContainer.addArrangedSubview(uploadStatusLabel)
        uploadContainer.addArrangedSubview(uploadProgressView)

        view.addSubview(uploadContainer)
        NSLayoutConstraint.activate([
            uploadContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            uploadContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            uploadContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func showUploadProgress(message: String, progress: Float) {
        uploadStatusLabel.text = message
        uploadProgressView.progress = progress
        uploadContainer.isHidden = false
    }

    private func updateUploadProgress(_ progress: Double) {
        uploadProgressView.progress = Float(progress)
    }

    private func hideUploadProgress() {
        uploadContainer.isHidden = true
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func makeExportFolder() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent("RoomScans", isDirectory: true)
        let exportFolder = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        return exportFolder
    }

    private func makeRoomExport(from capturedRoom: CapturedRoom, bounds: RoomBounds?) -> RoomExport {
        let roomSize = estimateRoomDimensions(from: capturedRoom, bounds: bounds)
        let furniture = capturedRoom.objects.map { object in
            let objectPosition = self.position(from: object.transform)
            return FurnitureItem(
                type: String(describing: object.category),
                position: [objectPosition.x, objectPosition.y, objectPosition.z]
            )
        }
        let dimensions = RoomDimensions(length: roomSize.x, width: roomSize.z, height: roomSize.y)
        return RoomExport(dimensions: dimensions, furniture: furniture)
    }

    private func estimateRoomDimensions(from capturedRoom: CapturedRoom, bounds: RoomBounds?) -> SIMD3<Float> {
        if let bounds {
            return bounds.max - bounds.min
        }
        return SIMD3<Float>(0, 0, 0)
    }

    private func makeRoomBounds(from capturedRoom: CapturedRoom) -> RoomBounds? {
        var boundsPoints: [SIMD3<Float>] = []

        let surfaces = capturedRoom.walls + capturedRoom.floors
        for surface in surfaces {
            let center = position(from: surface.transform)
            let half = surface.dimensions / 2
            boundsPoints.append(center - half)
            boundsPoints.append(center + half)
        }

        if boundsPoints.isEmpty {
            for object in capturedRoom.objects {
                let center = position(from: object.transform)
                let half = object.dimensions / 2
                boundsPoints.append(center - half)
                boundsPoints.append(center + half)
            }
        }

        guard var minPoint = boundsPoints.first else {
            return nil
        }

        var maxPoint = minPoint
        for point in boundsPoints.dropFirst() {
            minPoint = SIMD3<Float>(
                Swift.min(minPoint.x, point.x),
                Swift.min(minPoint.y, point.y),
                Swift.min(minPoint.z, point.z)
            )
            maxPoint = SIMD3<Float>(
                Swift.max(maxPoint.x, point.x),
                Swift.max(maxPoint.y, point.y),
                Swift.max(maxPoint.z, point.z)
            )
        }

        return RoomBounds(min: minPoint, max: maxPoint)
    }

    private func makeWallSegments(from capturedRoom: CapturedRoom) -> [LineSegment2D] {
        capturedRoom.walls.map { wall in
            let center = position(from: wall.transform)
            let axis = primaryAxis(from: wall.transform)
            let halfLength = wall.dimensions.x / 2
            let start = center - axis * halfLength
            let end = center + axis * halfLength
            return LineSegment2D(start: SIMD2<Float>(start.x, start.z), end: SIMD2<Float>(end.x, end.z))
        }
    }

    private func makeDoorSegments(from capturedRoom: CapturedRoom) -> [LineSegment2D] {
        capturedRoom.objects.compactMap { object in
            let type = String(describing: object.category).lowercased()
            guard type.contains("door") else { return nil }
            let center = position(from: object.transform)
            let axis = primaryAxis(from: object.transform)
            let halfLength = max(object.dimensions.x, object.dimensions.z) / 2
            let start = center - axis * halfLength
            let end = center + axis * halfLength
            return LineSegment2D(start: SIMD2<Float>(start.x, start.z), end: SIMD2<Float>(end.x, end.z))
        }
    }

    private func makeSVG(
        from export: RoomExport,
        bounds: RoomBounds?,
        wallSegments: [LineSegment2D],
        doorSegments: [LineSegment2D]
    ) -> String {
        let length = max(export.dimensions.length, 0)
        let width = max(export.dimensions.width, 0)
        let scale: Float = 100
        let margin: Float = 20
        let svgWidth = length * scale + margin * 2
        let svgHeight = width * scale + margin * 2

        let origin = bounds?.min ?? SIMD3<Float>(0, 0, 0)
        let origin2D = SIMD2<Float>(origin.x, origin.z)

        var svg = ""
        svg += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(fmt(svgWidth))\" height=\"\(fmt(svgHeight))\" viewBox=\"0 0 \(fmt(svgWidth)) \(fmt(svgHeight))\">"
        svg += "<rect x=\"\(fmt(margin))\" y=\"\(fmt(margin))\" width=\"\(fmt(length * scale))\" height=\"\(fmt(width * scale))\" fill=\"none\" stroke=\"#111827\" stroke-width=\"2\"/>"

        for wall in wallSegments {
            let (x1, y1) = svgPoint(for: wall.start, origin: origin2D, scale: scale, margin: margin)
            let (x2, y2) = svgPoint(for: wall.end, origin: origin2D, scale: scale, margin: margin)
            svg += "<line x1=\"\(fmt(x1))\" y1=\"\(fmt(y1))\" x2=\"\(fmt(x2))\" y2=\"\(fmt(y2))\" stroke=\"#111827\" stroke-width=\"3\"/>"
        }

        for door in doorSegments {
            let (x1, y1) = svgPoint(for: door.start, origin: origin2D, scale: scale, margin: margin)
            let (x2, y2) = svgPoint(for: door.end, origin: origin2D, scale: scale, margin: margin)
            svg += "<line x1=\"\(fmt(x1))\" y1=\"\(fmt(y1))\" x2=\"\(fmt(x2))\" y2=\"\(fmt(y2))\" stroke=\"#16a34a\" stroke-width=\"2\"/>"
        }

        for item in export.furniture {
            guard item.position.count >= 3 else { continue }
            let x = (item.position[0] - origin.x) * scale + margin
            let y = (item.position[2] - origin.z) * scale + margin
            svg += "<circle cx=\"\(fmt(x))\" cy=\"\(fmt(y))\" r=\"6\" fill=\"#2563eb\"/>"
            svg += "<text x=\"\(fmt(x + 8))\" y=\"\(fmt(y - 8))\" font-size=\"10\" fill=\"#111827\">\(item.type)</text>"
        }

        svg += "</svg>"
        return svg
    }

    private func fmt(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private func svgPoint(
        for point: SIMD2<Float>,
        origin: SIMD2<Float>,
        scale: Float,
        margin: Float
    ) -> (Float, Float) {
        let x = (point.x - origin.x) * scale + margin
        let y = (point.y - origin.y) * scale + margin
        return (x, y)
    }

    private func primaryAxis(from transform: simd_float4x4) -> SIMD3<Float> {
        var axis = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        if simd_length(axis) < 0.001 {
            axis = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        }
        if simd_length(axis) < 0.001 {
            axis = SIMD3<Float>(1, 0, 0)
        }
        return simd_normalize(axis)
    }

    private func position(from transform: simd_float4x4) -> SIMD3<Float> {
        let translation = transform.columns.3
        return SIMD3<Float>(translation.x, translation.y, translation.z)
    }
}

@available(iOS 16.0, *)
struct RoomScannerView: UIViewControllerRepresentable {
    var onFinish: (URL, URL, URL) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let scannerViewController = RoomScannerViewController()
        scannerViewController.onFinish = onFinish
        scannerViewController.onCancel = onCancel
        scannerViewController.onError = onError
        return UINavigationController(rootViewController: scannerViewController)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

private struct RoomBounds {
    let min: SIMD3<Float>
    let max: SIMD3<Float>
}

private struct LineSegment2D {
    let start: SIMD2<Float>
    let end: SIMD2<Float>
}
