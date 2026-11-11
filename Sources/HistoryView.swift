import SwiftUI
import UniformTypeIdentifiers

/// 签名历史记录
struct SignHistory: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var bundleId: String
    var version: String
    var certLabel: String
    var signedAt: Date
    var size: Int64
    var ok: Bool
    var outputPath: String
    var message: String
}

/// 历史页
struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if store.history.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 40)).foregroundColor(.gray)
                        Text("还没有签名记录").font(.system(size: 14)).foregroundColor(.gray)
                    }
                } else {
                    List {
                        ForEach(store.history) { h in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(h.name).font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    Image(systemName: h.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(h.ok ? .green : .red).font(.system(size: 12))
                                }
                                Text("\(h.bundleId) · v\(h.version)")
                                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                                HStack(spacing: 6) {
                                    Text(h.certLabel).font(.system(size: 10)).foregroundColor(.gray)
                                    Text("·").foregroundColor(.gray.opacity(0.5))
                                    Text(fmt(h.signedAt)).font(.system(size: 10)).foregroundColor(.gray)
                                }
                                if !h.message.isEmpty && !h.ok {
                                    Text(h.message).font(.system(size: 10)).foregroundColor(.red).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .onDelete { idx in
                            store.history.remove(atOffsets: idx)
                            store.saveHistory()
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("签名历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.history.isEmpty {
                        Button("清空") {
                            store.history.removeAll()
                            store.saveHistory()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}
