import Foundation

/// Owns one request and prevents a cancelled request from finishing a newer one.
@MainActor
final class RequestController {
    private var task: Task<Void, Never>?
    private var identifier: UUID?
    var isRunning: Bool { identifier != nil }

    @discardableResult
    func start(
        operation: @escaping @MainActor () async -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) -> Bool {
        guard !isRunning else { return false }
        let id = UUID()
        identifier = id
        task = Task {
            defer {
                if identifier == id {
                    identifier = nil
                    task = nil
                    onFinish()
                }
            }
            guard !Task.isCancelled else { return }
            await operation()
        }
        return true
    }

    func cancel() {
        task?.cancel()
        task = nil
        identifier = nil
    }
}
