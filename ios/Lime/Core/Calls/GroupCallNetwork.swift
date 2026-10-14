import Foundation
import Network

/// Whether the phone is on mobile data (a group call sends 480p there and 720p on Wi-Fi, LIME-112c).
@MainActor
protocol GroupCallNetwork: AnyObject {
    var isCellular: Bool { get }
    var onChange: ((Bool) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class SystemGroupCallNetwork: GroupCallNetwork {
    private let monitor = NWPathMonitor()
    private(set) var isCellular = false
    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Mobile data, and no Wi-Fi or wired path carrying the traffic.
            let cellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor in
                guard let self, self.isCellular != cellular else { return }
                self.isCellular = cellular
                self.onChange?(cellular)
            }
        }
        monitor.start(queue: DispatchQueue(label: "lime.group-call-network"))
    }

    func stop() { monitor.cancel() }
}
