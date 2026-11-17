import Foundation

func payload(_ doc: String) -> Payload {
    try! JSONDecoder().decode(Payload.self, from: Data("""
    {"v":1,"document":"\(doc)","progress":"/body/p[3]","percentage":0.42,"device":"PocketBook Verse Pro","device_id":"dev1","captured_at":1000,"sent_at":1060}
    """.utf8))
}

@MainActor func run() async {
    let store = Store()
    for d in ["docA", "docB", "docC"] { store.receive(payload(d)) }
    let cwa = CWA()
    cwa.serverURL = "http://127.0.0.1:8765"
    cwa.username = "alice"

    Keychain.password = "wrong"
    await cwa.uploadPending(store)
    print("WRONG_PW lastError=\(cwa.lastError ?? "nil") pending=\(store.pending.count)")

    Keychain.password = "secret"
    await cwa.uploadPending(store)
    for e in store.sorted.sorted(by: { $0.document < $1.document }) { print("STATUS", e.document, e.status) }
    print("lastError=\(cwa.lastError ?? "nil")")
    let readA = store.entries["docA"]!.readAt
    print("readAt offset ok:", abs(readA.timeIntervalSinceNow + 60) < 5)

    // Older progress for the same book must not replace the newer one.
    store.receive(payload("docA"), at: Date().addingTimeInterval(-3600))
    print("older ignored:", store.entries["docA"]!.readAt == readA)
    Keychain.password = nil
}
await run()
