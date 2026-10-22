import UIKit
import Vision

/// Reads the burned-in strip on a viewfinder frame (the Mac's `Viewfinder`):
/// the biggest "NNmm" in the picture, read on this iPhone, nothing leaving it.
enum Viewfinder {
    static func lens(in image: UIImage, done: @escaping (String?) -> Void) {
        guard let cg = image.cgImage else { done(nil); return }
        let request = VNRecognizeTextRequest { request, _ in
            let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { seen -> (text: String, height: CGFloat)? in
                    guard let top = seen.topCandidates(1).first else { return nil }
                    return (top.string, seen.boundingBox.height)
                }
            var best: (value: String, height: CGFloat)?
            for line in lines {
                guard let match = line.text.range(of: #"\b\d{1,3}(\.\d)?\s?mm\b"#,
                                                  options: [.regularExpression, .caseInsensitive]) else { continue }
                let value = line.text[match].lowercased().replacingOccurrences(of: " ", with: "")
                if best == nil || line.height > best!.height { best = (value, line.height) }
            }
            DispatchQueue.main.async { done(best?.value) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        DispatchQueue.global(qos: .userInitiated).async {
            if (try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])) == nil {
                DispatchQueue.main.async { done(nil) }
            }
        }
    }
}
