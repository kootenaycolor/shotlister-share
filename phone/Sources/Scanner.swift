import SwiftUI
import RoomPlan

/// Scanning a room, and what is kept afterwards.
///
/// Two things are saved, because they answer different questions and neither
/// substitutes for the other:
///
/// - **`scan.usdz`** — the room as a shape. This is what you look at, spin round,
///   and drop into a viewer. It cannot be measured reliably.
/// - **`scan.json`** — the same room as *measurements*: walls, doors, windows and
///   objects with their sizes and positions. This is what a floor plan is later
///   built from, and it is geometry rather than a guess, which is why the plan
///   says floor-plan conversion is arithmetic and not machine learning.
///
/// Throwing away the second is the easy mistake here; the viewer looks finished
/// without it and the floor plan then has nothing to be made from.
struct RoomScanner: UIViewControllerRepresentable {
    /// Where to put the two files.
    var usdz: URL
    var json: URL
    var onFinish: (Result<Void, Error>) -> Void

    func makeUIViewController(context: Context) -> ScanController {
        ScanController(usdz: usdz, json: json, onFinish: onFinish)
    }

    func updateUIViewController(_ controller: ScanController, context: Context) {}

    /// Whether this phone can scan at all. A phone without LiDAR is not a broken
    /// phone, so this is a fact to show rather than an error to raise.
    static var isSupported: Bool { RoomCaptureSession.isSupported }
}

final class ScanController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    private let usdz: URL
    private let json: URL
    private let onFinish: (Result<Void, Error>) -> Void

    private var captureView: RoomCaptureView!
    private var doneButton: UIButton!
    private var isScanning = false

    init(usdz: URL, json: URL, onFinish: @escaping (Result<Void, Error>) -> Void) {
        self.usdz = usdz
        self.json = json
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        captureView = RoomCaptureView(frame: view.bounds)
        captureView.captureSession.delegate = self
        captureView.delegate = self
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(captureView)

        // One button, and it says what it does. Apple's own sample hides
        // finishing behind a navigation bar; on a scout the phone is at arm's
        // length and the target wants to be big.
        var config = UIButton.Configuration.filled()
        config.title = "Done scanning"
        config.cornerStyle = .capsule
        config.buttonSize = .large
        doneButton = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.stop()
        })
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)
        NSLayoutConstraint.activate([
            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isScanning else { return }
        isScanning = true
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    private func stop() {
        guard isScanning else { return }
        isScanning = false
        doneButton.isEnabled = false
        doneButton.configuration?.title = "Finishing…"
        captureView.captureSession.stop()
    }

    // Let RoomPlan do its own processing pass — it is what turns a cloud of
    // surfaces into named walls and doors.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            onFinish(.failure(error))
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: usdz.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try processedResult.export(to: usdz, exportOptions: .parametric)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(processedResult).write(to: json, options: .atomic)

            onFinish(.success(()))
        } catch {
            onFinish(.failure(error))
        }
    }
}
