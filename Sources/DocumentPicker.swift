import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 原生文档选择器（asCopy: true）。
/// SwiftUI 的 fileImporter 对没有注册 UTI 的文件（.p12 / .mobileprovision）
/// 会整列表置灰点不动，原生 picker 用 asCopy 模式没有这个问题。
struct DocumentPicker: UIViewControllerRepresentable {
    let allowsMultiple: Bool
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // [.item] = public.item，所有文件的根类型
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        vc.allowsMultipleSelection = allowsMultiple
        vc.delegate = context.coordinator
        vc.shouldShowFileExtensions = true
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coord: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ p: DocumentPicker) { parent = p }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

/// 用 sheet 承载，避免 SwiftUI fileImporter 的置灰问题
struct DocumentPickerSheet: ViewModifier {
    @Binding var isPresented: Bool
    let allowsMultiple: Bool
    let onPick: ([URL]) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            DocumentPicker(allowsMultiple: allowsMultiple) { urls in
                isPresented = false
                onPick(urls)
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func documentPicker(isPresented: Binding<Bool>,
                        allowsMultiple: Bool = false,
                        onPick: @escaping ([URL]) -> Void) -> some View {
        modifier(DocumentPickerSheet(isPresented: isPresented,
                                     allowsMultiple: allowsMultiple,
                                     onPick: onPick))
    }
}
