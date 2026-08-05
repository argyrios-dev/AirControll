import CoreGraphics
import Foundation
@preconcurrency import Vision

struct HandPoseFeatureExtractor {
  private struct HandData {
    var points: [VNHumanHandPoseObservation.JointName: CGPoint]
    var minimumConfidence: Double
    var handedness: Double
    var palmCenter: CGPoint
    var scale: Double
    var orientation: Double
  }

  private let jointOrder: [VNHumanHandPoseObservation.JointName] = [
    .wrist,
    .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
    .indexMCP, .indexPIP, .indexDIP, .indexTip,
    .middleMCP, .middlePIP, .middleDIP, .middleTip,
    .ringMCP, .ringPIP, .ringDIP, .ringTip,
    .littleMCP, .littlePIP, .littleDIP, .littleTip,
  ]

  private let jointLabels: [String] = [
    "wrist",
    "thumb.cmc", "thumb.mp", "thumb.ip", "thumb.tip",
    "index.mcp", "index.pip", "index.dip", "index.tip",
    "middle.mcp", "middle.pip", "middle.dip", "middle.tip",
    "ring.mcp", "ring.pip", "ring.dip", "ring.tip",
    "little.mcp", "little.pip", "little.dip", "little.tip",
  ]

  func extract(
    from observations: [VNHumanHandPoseObservation],
    minimumConfidence: Double
  ) throws -> ExtractedFeatureVector {
    var validHands: [HandData] = []
    var firstExtractionError: Error?
    for observation in observations.prefix(2) {
      do {
        validHands.append(
          try makeHandData(from: observation, minimumConfidence: minimumConfidence))
      } catch {
        if firstExtractionError == nil { firstExtractionError = error }
      }
    }
    guard !validHands.isEmpty else {
      throw firstExtractionError ?? FeatureExtractionError.noHands
    }

    let sortedHands = validHands.sorted {
      if $0.handedness != $1.handedness { return $0.handedness < $1.handedness }
      return $0.palmCenter.x < $1.palmCenter.x
    }

    var names: [String] = []
    var values: [Double] = []
    var weights: [Double] = []

    for slot in 0..<2 {
      if slot < sortedHands.count {
        appendFeatures(
          for: sortedHands[slot], slot: slot, names: &names, values: &values, weights: &weights)
      } else {
        appendEmptyHand(slot: slot, names: &names, values: &values, weights: &weights)
      }
    }

    names.append("hands.count")
    values.append(Double(sortedHands.count) / 2.0)
    weights.append(4.0)

    let interHandDistance: Double
    let interHandAngle: Double
    if sortedHands.count == 2 {
      let delta = CGPoint(
        x: sortedHands[1].palmCenter.x - sortedHands[0].palmCenter.x,
        y: sortedHands[1].palmCenter.y - sortedHands[0].palmCenter.y
      )
      let averageScale = max(0.0001, (sortedHands[0].scale + sortedHands[1].scale) / 2.0)
      interHandDistance = hypot(delta.x, delta.y) / averageScale
      interHandAngle = atan2(delta.y, delta.x) / .pi
    } else {
      interHandDistance = 0
      interHandAngle = 0
    }
    names.append(contentsOf: ["hands.relativeDistance", "hands.relativeAngle"])
    values.append(contentsOf: [interHandDistance, interHandAngle])
    weights.append(contentsOf: [2.0, 0.35])

    let singleHandSide: HandSide?
    if sortedHands.count == 1, sortedHands[0].handedness < -0.5 {
      singleHandSide = .left
    } else if sortedHands.count == 1, sortedHands[0].handedness > 0.5 {
      singleHandSide = .right
    } else {
      singleHandSide = nil
    }

    return ExtractedFeatureVector(
      names: names,
      values: values.map(Self.finite),
      weights: weights,
      handCount: sortedHands.count,
      minimumConfidence: sortedHands.map(\.minimumConfidence).min() ?? 0,
      singleHandSide: singleHandSide
    )
  }

  private func makeHandData(
    from observation: VNHumanHandPoseObservation,
    minimumConfidence: Double
  ) throws -> HandData {
    var points: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
    var confidences: [Double] = []

    for joint in jointOrder {
      let recognized = try observation.recognizedPoint(joint)
      let confidence = Double(recognized.confidence)
      guard confidence >= minimumConfidence else {
        throw FeatureExtractionError.lowConfidence(joint.rawValue.rawValue, confidence)
      }
      points[joint] = CGPoint(x: recognized.location.x, y: recognized.location.y)
      confidences.append(confidence)
    }

    guard
      let wrist = points[.wrist],
      let indexMCP = points[.indexMCP],
      let middleMCP = points[.middleMCP],
      let ringMCP = points[.ringMCP],
      let littleMCP = points[.littleMCP]
    else {
      throw FeatureExtractionError.missingLandmarks
    }

    let palmCenter = CGPoint(
      x: (wrist.x + indexMCP.x + middleMCP.x + ringMCP.x + littleMCP.x) / 5.0,
      y: (wrist.y + indexMCP.y + middleMCP.y + ringMCP.y + littleMCP.y) / 5.0
    )
    let palmWidth = max(0.0001, hypot(indexMCP.x - littleMCP.x, indexMCP.y - littleMCP.y))
    let palmLength = max(0.0001, hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y))
    let scale = max(0.0001, (palmWidth + palmLength) / 2.0)
    let orientation = atan2(middleMCP.y - wrist.y, middleMCP.x - wrist.x)

    let handedness: Double
    switch observation.chirality {
    case .left: handedness = -1.0
    case .right: handedness = 1.0
    default: handedness = 0.0
    }

    return HandData(
      points: points,
      minimumConfidence: confidences.min() ?? 0,
      handedness: handedness,
      palmCenter: palmCenter,
      scale: scale,
      orientation: orientation
    )
  }

  private func appendFeatures(
    for hand: HandData,
    slot: Int,
    names: inout [String],
    values: inout [Double],
    weights: inout [Double]
  ) {
    let prefix = "hand\(slot + 1)"
    let rotation = (.pi / 2.0) - hand.orientation
    let cosine = cos(rotation)
    let sine = sin(rotation)

    for (index, joint) in jointOrder.enumerated() {
      let point = hand.points[joint] ?? hand.palmCenter
      let dx = (point.x - hand.palmCenter.x) / hand.scale
      let dy = (point.y - hand.palmCenter.y) / hand.scale
      let rx = dx * cosine - dy * sine
      let ry = dx * sine + dy * cosine
      names.append("\(prefix).\(jointLabels[index]).x")
      names.append("\(prefix).\(jointLabels[index]).y")
      values.append(rx)
      values.append(ry)
      weights.append(1.0)
      weights.append(1.0)
    }

    names.append(contentsOf: [
      "\(prefix).palmCenter.x",
      "\(prefix).palmCenter.y",
      "\(prefix).orientation.sin",
      "\(prefix).orientation.cos",
      "\(prefix).handedness",
      "\(prefix).present",
    ])
    values.append(contentsOf: [
      Double(hand.palmCenter.x * 2.0 - 1.0),
      Double(hand.palmCenter.y * 2.0 - 1.0),
      sin(hand.orientation),
      cos(hand.orientation),
      hand.handedness,
      1.0,
    ])
    weights.append(contentsOf: [0.0001, 0.0001, 0.35, 0.35, 0.4, 4.0])

    let fingerChains: [(String, [VNHumanHandPoseObservation.JointName])] = [
      ("thumb", [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip]),
      ("index", [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]),
      ("middle", [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip]),
      ("ring", [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip]),
      ("little", [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]),
    ]

    for (fingerName, chain) in fingerChains {
      let chainPoints = chain.compactMap { hand.points[$0] }
      guard chainPoints.count == chain.count else { continue }
      let chainLength = zip(chainPoints, chainPoints.dropFirst()).reduce(0.0) {
        $0 + hypot($1.0.x - $1.1.x, $1.0.y - $1.1.y)
      }
      let direct = hypot(
        chainPoints.last!.x - chainPoints.first!.x,
        chainPoints.last!.y - chainPoints.first!.y
      )
      let extensionValue = chainLength > 0 ? direct / chainLength : 0
      let angles = (1..<(chainPoints.count - 1)).map {
        Self.normalizedAngle(chainPoints[$0 - 1], chainPoints[$0], chainPoints[$0 + 1])
      }
      let curl = angles.isEmpty ? 0 : 1.0 - angles.reduce(0, +) / Double(angles.count)
      for (angleIndex, angle) in angles.enumerated() {
        names.append("\(prefix).\(fingerName).angle\(angleIndex + 1)")
        values.append(angle)
        weights.append(1.3)
      }
      names.append("\(prefix).\(fingerName).extension")
      names.append("\(prefix).\(fingerName).curl")
      values.append(extensionValue)
      values.append(curl)
      weights.append(2.0)
      weights.append(2.0)
    }

    let tips: [(String, VNHumanHandPoseObservation.JointName)] = [
      ("thumb", .thumbTip), ("index", .indexTip), ("middle", .middleTip),
      ("ring", .ringTip), ("little", .littleTip),
    ]
    if let wrist = hand.points[.wrist] {
      for (name, tipJoint) in tips {
        if let tip = hand.points[tipJoint] {
          names.append("\(prefix).distance.wrist.\(name)Tip")
          values.append(hypot(tip.x - wrist.x, tip.y - wrist.y) / hand.scale)
          weights.append(1.4)
        }
      }
    }
    for pair in zip(tips, tips.dropFirst()) {
      if let a = hand.points[pair.0.1], let b = hand.points[pair.1.1] {
        names.append("\(prefix).distance.\(pair.0.0)Tip.\(pair.1.0)Tip")
        values.append(hypot(a.x - b.x, a.y - b.y) / hand.scale)
        weights.append(1.2)
      }
    }
  }

  private func appendEmptyHand(
    slot: Int,
    names: inout [String],
    values: inout [Double],
    weights: inout [Double]
  ) {
    let before = names.count
    let dummy = HandData(
      points: Dictionary(uniqueKeysWithValues: jointOrder.map { ($0, .zero) }),
      minimumConfidence: 0,
      handedness: 0,
      palmCenter: .zero,
      scale: 1,
      orientation: 0
    )
    appendFeatures(for: dummy, slot: slot, names: &names, values: &values, weights: &weights)
    for index in before..<values.count { values[index] = 0 }
    if let presentIndex = names.lastIndex(of: "hand\(slot + 1).present") {
      values[presentIndex] = 0
    }
  }

  private static func normalizedAngle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
    let ab = CGVector(dx: a.x - b.x, dy: a.y - b.y)
    let cb = CGVector(dx: c.x - b.x, dy: c.y - b.y)
    let denominator = max(0.000001, hypot(ab.dx, ab.dy) * hypot(cb.dx, cb.dy))
    let cosine = min(1.0, max(-1.0, (ab.dx * cb.dx + ab.dy * cb.dy) / denominator))
    return acos(cosine) / .pi
  }

  private static func finite(_ value: Double) -> Double {
    value.isFinite ? value : 0
  }
}

enum FeatureExtractionError: LocalizedError {
  case noHands
  case missingLandmarks
  case lowConfidence(String, Double)

  var errorDescription: String? {
    switch self {
    case .noHands: "No hand was detected."
    case .missingLandmarks: "Required hand landmarks are missing."
    case .lowConfidence(let joint, let confidence):
      "Landmark \(joint) confidence was too low (\(String(format: "%.2f", confidence)))."
    }
  }
}
