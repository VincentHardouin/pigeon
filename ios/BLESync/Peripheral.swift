import CoreBluetooth
import Foundation

/// GATT server the PocketBook connects to (README §7).
final class Peripheral: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let serviceUUID = CBUUID(string: "947694FE-0425-4E30-84BC-FB783E781EAD")
    static let progressUUID = CBUUID(string: "1FD42B59-27A4-49F9-B36B-C1D0F9C445B2")

    @Published var state = "…"
    @Published var isReady = false

    var onPayload: (@MainActor (Payload) -> Void)?
    private var manager: CBPeripheralManager!
    private var serviceAdded = false

    override init() {
        super.init()
        // Restoration lets iOS relaunch the app in the background when the PocketBook writes.
        manager = CBPeripheralManager(delegate: self, queue: nil,
                                      options: [CBPeripheralManagerOptionRestoreIdentifierKey: "blesync-peripheral"])
    }

    func peripheralManager(_ m: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] ?? []
        serviceAdded = services.contains { $0.uuid == Self.serviceUUID }
    }

    func peripheralManagerDidUpdateState(_ m: CBPeripheralManager) {
        state = switch m.state {
        case .poweredOn: "Bluetooth prêt"
        case .poweredOff: "Bluetooth éteint"
        case .unauthorized: "Bluetooth non autorisé"
        default: "Bluetooth indisponible"
        }
        #if targetEnvironment(simulator)
        // ponytail: the simulator has no Bluetooth; pretend it is ready so screenshots show the real layout.
        state = "Bluetooth prêt"
        isReady = true
        return
        #else
        isReady = m.state == .poweredOn
        guard isReady else { return }
        #endif
        if serviceAdded {
            startAdvertising()
            return
        }
        // ponytail: no encryption, the kernel can't resolve the iPhone's rotating address so a bond would never be reused.
        let progress = CBMutableCharacteristic(type: Self.progressUUID, properties: [.write], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [progress]
        m.add(service)
    }

    func peripheralManager(_ m: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { state = "Erreur service : \(error.localizedDescription)"; return }
        serviceAdded = true
        startAdvertising()
    }

    private func startAdvertising() {
        guard !manager.isAdvertising else { return }
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                                  CBAdvertisementDataLocalNameKey: "BLESync"])
    }

    func peripheralManager(_ m: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // A long write arrives as several chunks with offsets.
        let data = requests.filter { $0.characteristic.uuid == Self.progressUUID }
            .sorted { $0.offset < $1.offset }
            .reduce(into: Data()) { $0.append($1.value ?? Data()) }
        guard let first = requests.first else { return }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            // An error makes blesync.sh keep the entry and retry later.
            m.respond(to: first, withResult: .unlikelyError)
            return
        }
        m.respond(to: first, withResult: .success)
        // Delegate runs on the main queue (queue: nil).
        MainActor.assumeIsolated { onPayload?(payload) }
    }
}
