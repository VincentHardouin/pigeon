import Network
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppModel {
    static let shared = AppModel()
    let store = Store()
    let cwa = CWA()
    let peripheral = Peripheral()
    private let network = NWPathMonitor()

    private init() {
        peripheral.onPayload = { [unowned self] payload in
            store.receive(payload)
            upload()
        }
        network.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in AppModel.shared.upload() }
        }
        network.start(queue: .main)
    }

    func upload() {
        #if canImport(UIKit)
        // A BLE write wakes the app for a few seconds only: ask for time to finish the HTTP calls.
        let task = UIApplication.shared.beginBackgroundTask()
        Task {
            await cwa.uploadPending(store)
            UIApplication.shared.endBackgroundTask(task)
        }
        #else
        Task { await cwa.uploadPending(store) }
        #endif
    }
}

#if canImport(UIKit)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // BLE state restoration relaunches the app in the background without any scene: the peripheral must exist from launch.
        _ = AppModel.shared
        return true
    }
}
#endif

@main
struct PigeonApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            let model = AppModel.shared
            ContentView(store: model.store, cwa: model.cwa, peripheral: model.peripheral, upload: model.upload)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { AppModel.shared.upload() }
        }
    }
}
