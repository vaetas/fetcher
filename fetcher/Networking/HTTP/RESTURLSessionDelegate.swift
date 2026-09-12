import Foundation

final class RESTURLSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let followRedirects: Bool
    private let lock = NSLock()
    private var _latestMetrics: URLSessionTaskMetrics?
    private var _latestRedirects: [RedirectEvent] = []
    private var _redirectsByTask: [Int: [RedirectEvent]] = [:]

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    var latestMetrics: URLSessionTaskMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return _latestMetrics
    }

    var latestRedirects: [RedirectEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _latestRedirects
    }

    func metrics(for task: URLSessionTask) -> URLSessionTaskMetrics? {
        latestMetrics
    }

    func redirects(for task: URLSessionTask) -> [RedirectEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _redirectsByTask[task.taskIdentifier] ?? _latestRedirects
    }

    func clear(task: URLSessionTask) {
        lock.lock()
        defer { lock.unlock() }
        _redirectsByTask.removeValue(forKey: task.taskIdentifier)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        var events = _redirectsByTask[task.taskIdentifier] ?? []
        events.append(
            RedirectEvent(
                statusCode: response.statusCode,
                fromURL: task.currentRequest?.url ?? task.originalRequest?.url,
                toURL: request.url
            )
        )
        _redirectsByTask[task.taskIdentifier] = events
        _latestRedirects = events
        lock.unlock()

        completionHandler(followRedirects ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        _latestMetrics = metrics
        _latestRedirects = _redirectsByTask[task.taskIdentifier] ?? _latestRedirects
        lock.unlock()
    }
}
