enum UpstreamFailure: Error, CustomStringConvertible {
    case closedBeforeResponseCompleted
    case missingResponseHead
    case responseTimedOut

    var description: String {
        switch self {
        case .closedBeforeResponseCompleted:
            "Connection closed before the response completed"
        case .missingResponseHead:
            "Response ended without a response head"
        case .responseTimedOut:
            "No upstream response data received for 12 seconds"
        }
    }
}
