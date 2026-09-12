import Foundation

enum RequestMetricsCollector {
    static func collect(from metrics: URLSessionTaskMetrics?) -> RequestMetrics {
        guard let metrics else {
            return RequestMetrics(redirectCount: 0)
        }

        let transactions = metrics.transactionMetrics
        let first = transactions.first
        let last = transactions.last

        func duration(_ start: Date?, _ end: Date?) -> TimeInterval? {
            guard let start, let end else { return nil }
            return end.timeIntervalSince(start)
        }

        let total: TimeInterval?
        if let start = first?.fetchStartDate, let end = last?.responseEndDate {
            total = end.timeIntervalSince(start)
        } else {
            total = nil
        }

        let dns = duration(first?.domainLookupStartDate, first?.domainLookupEndDate)
        let connect = duration(first?.connectStartDate, first?.connectEndDate)
        let tls = duration(first?.secureConnectionStartDate, first?.secureConnectionEndDate)
        let request = duration(last?.requestStartDate, last?.requestEndDate)
        let ttfb = duration(last?.requestEndDate, last?.responseStartDate)
        let download = duration(last?.responseStartDate, last?.responseEndDate)

        let protocolName = last?.networkProtocolName
        let reused = last?.isReusedConnection

        return RequestMetrics(
            totalDuration: total,
            dnsLookup: dns,
            tcpConnect: connect,
            tlsHandshake: tls,
            requestDuration: request,
            timeToFirstByte: ttfb,
            responseDownload: download,
            negotiatedProtocol: protocolName,
            reusedConnection: reused,
            redirectCount: max(0, transactions.count - 1)
        )
    }
}
