//
//  USDZPreviewView.swift
//  whc-lidar-ios
//
//  Created by Matěj Kocanda on 16.02.2026.
//

import QuickLook
import SwiftUI

struct USDZPreviewView: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}
