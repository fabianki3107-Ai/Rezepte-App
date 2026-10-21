import Foundation
import Vision
import CoreGraphics
import UIKit

/// Eine erkannte Textzeile mit Position (normalisierte Vision-Koordinaten, Ursprung unten links).
struct OCRLine: Hashable, Sendable {
    let text: String
    let confidence: Float
    let boundingBox: CGRect

    /// Oberkante in "Leserichtung" (0 = oben), hilfreich zum Sortieren.
    var top: CGFloat { 1 - boundingBox.maxY }
    var left: CGFloat { boundingBox.minX }
}

/// Ergebnis einer OCR-Erkennung über ein Bild.
struct OCRResult: Sendable {
    let lines: [OCRLine]
    let imageSize: CGSize

    /// Zeilen in Leserichtung, mit Zeilenumbrüchen – Eingabe für den Rezept-Parser.
    var text: String { lines.map(\.text).joined(separator: "\n") }

    /// Mittlere Konfidenz (0...1), gewichtet nach Zeichenanzahl.
    var averageConfidence: Double {
        let weighted = lines.reduce(into: (sum: 0.0, count: 0.0)) { acc, line in
            let weight = Double(line.text.count)
            acc.sum += Double(line.confidence) * weight
            acc.count += weight
        }
        return weighted.count > 0 ? weighted.sum / weighted.count : 0
    }

    static let empty = OCRResult(lines: [], imageSize: .zero)
}

enum OCRError: LocalizedError {
    case invalidImage
    case noTextFound
    case recognitionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Das Bild konnte nicht gelesen werden."
        case .noTextFound: return "Im Bild wurde kein Text erkannt. Versuche einen schärferen Screenshot."
        case .recognitionFailed(let error): return "Texterkennung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

/// Kapselt Apple Vision (`VNRecognizeTextRequest`) für den Screenshot-/Foto-Import.
///
/// - Läuft vollständig on-device, kein Netzwerk.
/// - `accurate`-Modus mit Sprachkorrektur für Deutsch und Englisch.
/// - Sortiert Beobachtungen in Leserichtung und fasst Wörter derselben Zeile zusammen,
///   damit "200 g" und "Mehl" nicht auseinanderfallen.
actor VisionOCRManager {
    static let shared = VisionOCRManager()

    /// Bilder größer als diese Kante werden vor der Erkennung verkleinert (Speicher & Tempo).
    private let maxDimension: CGFloat = 3000
    private let languages = ["de-DE", "en-US"]

    func recognizeText(in image: UIImage) async throws -> OCRResult {
        let prepared = Self.downscaledIfNeeded(image, maxDimension: maxDimension)
        guard let cgImage = prepared.cgImage else { throw OCRError.invalidImage }
        let orientation = CGImagePropertyOrientation(prepared.imageOrientation)
        return try await recognizeText(in: cgImage, orientation: orientation)
    }

    func recognizeText(in cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> OCRResult {
        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            // Vision ruft den Completion-Handler auch auf, wenn `perform` wirft – nur einmal fortsetzen.
            let once = ResumeOnce(continuation)
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    once.resume(.failure(OCRError.recognitionFailed(underlying: error)))
                    return
                }
                let results = (request.results as? [VNRecognizedTextObservation]) ?? []
                once.resume(.success(results))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }
            request.minimumTextHeight = 0.012 // filtert winzige UI-Reste (Uhrzeit, Akkuanzeige)

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                once.resume(.failure(OCRError.recognitionFailed(underlying: error)))
            }
        }

        let lines = Self.assembleLines(from: observations)
        guard !lines.isEmpty else { throw OCRError.noTextFound }
        return OCRResult(lines: lines, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Layout-Rekonstruktion

    /// Vision liefert pro Textblock eine Beobachtung. Wir sortieren nach Leserichtung
    /// und verschmelzen Beobachtungen, die vertikal überlappen (gleiche Zeile, z. B. zweispaltige Mengen).
    static func assembleLines(from observations: [VNRecognizedTextObservation]) -> [OCRLine] {
        let candidates: [OCRLine] = observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(text: text, confidence: best.confidence, boundingBox: observation.boundingBox)
        }
        .sorted { lhs, rhs in
            if abs(lhs.top - rhs.top) > 0.004 { return lhs.top < rhs.top }
            return lhs.left < rhs.left
        }

        var merged: [OCRLine] = []
        for line in candidates {
            if let last = merged.last, Self.shareRow(last, line) {
                let combined = OCRLine(
                    text: last.text + " " + line.text,
                    confidence: min(last.confidence, line.confidence),
                    boundingBox: last.boundingBox.union(line.boundingBox)
                )
                merged[merged.count - 1] = combined
            } else {
                merged.append(line)
            }
        }
        return merged
    }

    /// Zwei Boxen gelten als eine Zeile, wenn sie sich vertikal zu mindestens 50 % überlappen
    /// und horizontal nicht weiter als eine Zeilenhöhe auseinanderliegen.
    private static func shareRow(_ a: OCRLine, _ b: OCRLine) -> Bool {
        let overlap = min(a.boundingBox.maxY, b.boundingBox.maxY) - max(a.boundingBox.minY, b.boundingBox.minY)
        let minHeight = min(a.boundingBox.height, b.boundingBox.height)
        guard minHeight > 0, overlap / minHeight >= 0.5 else { return false }
        let horizontalGap = b.boundingBox.minX - a.boundingBox.maxX
        return horizontalGap >= -0.01 && horizontalGap < minHeight * 1.5
    }

    private static func downscaledIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// Schützt eine Continuation vor mehrfachem Resume.
private final class ResumeOnce<T> {
    private var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
