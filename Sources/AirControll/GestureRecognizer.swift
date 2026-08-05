import Foundation

private enum GestureFeatureMath {
  static func effectiveWeight(for name: String, storedWeight: Double) -> Double {
    if name.hasSuffix(".palmCenter.x") || name.hasSuffix(".palmCenter.y") {
      return 0.0001
    }
    if name.hasSuffix(".orientation.sin") || name.hasSuffix(".orientation.cos") {
      return min(storedWeight, 0.35)
    }
    if name.hasSuffix(".handedness") {
      return min(storedWeight, 0.25)
    }
    if name == "hands.relativeAngle" {
      return min(storedWeight, 0.35)
    }
    return storedWeight
  }

  static func varianceFloor(for name: String) -> Double {
    if name.hasSuffix(".palmCenter.x") || name.hasSuffix(".palmCenter.y") {
      return 1.0
    }
    if name.hasSuffix(".orientation.sin") || name.hasSuffix(".orientation.cos")
      || name == "hands.relativeAngle"
    {
      return 0.01
    }
    if name.hasSuffix(".x") || name.hasSuffix(".y") {
      return 0.0025
    }
    return 0.0016
  }

  static func normalizedDistance(
    _ lhs: [Double],
    _ rhs: [Double],
    names: [String],
    weights: [Double]
  ) -> Double {
    guard lhs.count == rhs.count, lhs.count == names.count, lhs.count == weights.count else {
      return .infinity
    }
    var total = 0.0
    var weightTotal = 0.0
    for index in lhs.indices {
      let weight = effectiveWeight(for: names[index], storedWeight: weights[index])
      total += weight * pow(lhs[index] - rhs[index], 2)
      weightTotal += weight
    }
    return sqrt(total / max(0.0001, weightTotal))
  }

  static func varianceAwareDistance(
    _ values: [Double],
    _ mean: [Double],
    variance: [Double],
    names: [String],
    weights: [Double]
  ) -> Double {
    guard values.count == mean.count,
      values.count == variance.count,
      values.count == names.count,
      values.count == weights.count
    else {
      return .infinity
    }

    var total = 0.0
    var weightTotal = 0.0
    for index in values.indices {
      let weight = effectiveWeight(for: names[index], storedWeight: weights[index])
      let floor = varianceFloor(for: names[index])
      let delta = values[index] - mean[index]
      total += weight * delta * delta / max(floor, variance[index])
      weightTotal += weight
    }
    return sqrt(total / max(0.0001, weightTotal))
  }

  static func mirroredOneHandValues(_ values: [Double], names: [String]) -> [Double] {
    guard values.count == names.count else { return values }
    var mirrored = values
    for index in mirrored.indices {
      let name = names[index]
      guard name.hasPrefix("hand1.") else { continue }
      if name.hasSuffix(".x")
        || name.hasSuffix(".orientation.cos")
        || name.hasSuffix(".handedness")
      {
        mirrored[index] = -mirrored[index]
      }
    }
    return mirrored
  }
}

struct GestureRecorder {
  let gestureID: UUID
  let expectedHandCount: Int?
  let targetSampleCount: Int

  private(set) var samples: [ExtractedFeatureVector] = []
  private(set) var rejectedCount = 0
  private var recentValues: [[Double]] = []
  private var recordedHandCount: Int?
  private var recordedSingleHandSide: HandSide?

  init(gestureID: UUID, expectedHandCount: Int?, targetSampleCount: Int) {
    self.gestureID = gestureID
    self.expectedHandCount = expectedHandCount
    self.targetSampleCount = targetSampleCount
  }

  mutating func accept(_ vector: ExtractedFeatureVector) -> Bool {
    let requiredHandCount = expectedHandCount ?? recordedHandCount
    if let requiredHandCount, vector.handCount != requiredHandCount {
      rejectedCount += 1
      return false
    }
    if recordedHandCount == nil { recordedHandCount = vector.handCount }

    if vector.handCount == 1 {
      if let recordedSingleHandSide, recordedSingleHandSide != vector.singleHandSide {
        rejectedCount += 1
        return false
      }
      if recordedSingleHandSide == nil {
        recordedSingleHandSide = vector.singleHandSide
      }
    }

    if let first = samples.first,
      first.names != vector.names || first.values.count != vector.values.count
    {
      rejectedCount += 1
      return false
    }

    if recentValues.count >= 4 {
      let recentMean = Self.mean(recentValues)
      let motion = GestureFeatureMath.normalizedDistance(
        vector.values,
        recentMean,
        names: vector.names,
        weights: vector.weights
      )
      guard motion < 0.20 else {
        rejectedCount += 1
        recentValues.removeAll(keepingCapacity: true)
        return false
      }
    }

    if samples.count >= 10 {
      let runningMean = Self.mean(samples.map(\.values))
      let distance = GestureFeatureMath.normalizedDistance(
        vector.values,
        runningMean,
        names: vector.names,
        weights: vector.weights
      )
      guard distance < 0.40 else {
        rejectedCount += 1
        return false
      }
    }

    recentValues.append(vector.values)
    if recentValues.count > 6 { recentValues.removeFirst() }
    samples.append(vector)
    return true
  }

  var isComplete: Bool { samples.count >= targetSampleCount }

  mutating func rejectOne() {
    rejectedCount += 1
  }

  func makeTemplate(recordingDate: Date = Date()) throws -> GestureTemplate {
    guard samples.count >= 24, let first = samples.first else {
      throw GestureRecordingError.insufficientStableSamples
    }

    let initialMean = Self.mean(samples.map(\.values))
    let distances = samples.map {
      GestureFeatureMath.normalizedDistance(
        $0.values,
        initialMean,
        names: $0.names,
        weights: $0.weights
      )
    }
    let median = Self.median(distances)
    let deviations = distances.map { abs($0 - median) }
    let mad = max(0.005, Self.median(deviations))
    let filtered = zip(samples, distances).filter { $0.1 <= median + 2.8 * mad }.map(\.0)
    guard filtered.count >= 24 else { throw GestureRecordingError.inconsistentSamples }

    let mean = Self.mean(filtered.map(\.values))
    let rawVariance = Self.variance(filtered.map(\.values), mean: mean)
    let variance = rawVariance.enumerated().map { index, value in
      max(value, GestureFeatureMath.varianceFloor(for: first.names[index]))
    }
    let trainingScores = filtered.map {
      GestureFeatureMath.varianceAwareDistance(
        $0.values,
        mean,
        variance: variance,
        names: $0.names,
        weights: $0.weights
      )
    }.sorted()
    let percentileIndex = min(
      trainingScores.count - 1,
      Int(Double(trainingScores.count - 1) * 0.95)
    )
    let p95 = trainingScores[percentileIndex]
    let threshold = min(4.8, max(1.45, p95 * 1.65 + 0.25))

    return GestureTemplate(
      featureNames: first.names,
      mean: mean,
      variance: variance,
      weights: first.weights,
      threshold: threshold,
      sampleCount: filtered.count,
      recordingDate: recordingDate,
      expectedHandCount: expectedHandCount ?? recordedHandCount ?? first.handCount
    )
  }

  private static func mean(_ values: [[Double]]) -> [Double] {
    guard let first = values.first else { return [] }
    var output = Array(repeating: 0.0, count: first.count)
    for vector in values {
      for index in output.indices { output[index] += vector[index] }
    }
    let divisor = Double(values.count)
    return output.map { $0 / divisor }
  }

  private static func variance(_ values: [[Double]], mean: [Double]) -> [Double] {
    var output = Array(repeating: 0.0, count: mean.count)
    for vector in values {
      for index in output.indices {
        let delta = vector[index] - mean[index]
        output[index] += delta * delta
      }
    }
    let divisor = Double(max(1, values.count - 1))
    return output.map { $0 / divisor }
  }

  private static func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }
}

struct DeterministicGestureMatcher {
  struct Match: Equatable {
    var gestureID: UUID
    var score: Double
    var threshold: Double
  }

  func bestMatch(
    vector: ExtractedFeatureVector,
    gestures: [GestureDefinition],
    handUsageMode: HandUsageMode
  ) -> Match? {
    if vector.handCount == 1, !handUsageMode.accepts(vector.singleHandSide) {
      return nil
    }

    let mirroredValues =
      vector.handCount == 1
      ? GestureFeatureMath.mirroredOneHandValues(vector.values, names: vector.names)
      : nil

    var candidates: [Match] = []
    for gesture in gestures {
      guard let template = gesture.template,
        template.expectedHandCount == vector.handCount,
        template.featureNames == vector.names,
        template.mean.count == vector.values.count,
        template.variance.count == vector.values.count,
        template.weights.count == vector.values.count
      else { continue }

      let directScore = GestureFeatureMath.varianceAwareDistance(
        vector.values,
        template.mean,
        variance: template.variance,
        names: template.featureNames,
        weights: template.weights
      )

      let score: Double
      if let mirroredValues {
        let mirroredScore = GestureFeatureMath.varianceAwareDistance(
          mirroredValues,
          template.mean,
          variance: template.variance,
          names: template.featureNames,
          weights: template.weights
        )
        score = min(directScore, mirroredScore)
      } else {
        score = directScore
      }

      guard score <= template.threshold else { continue }
      candidates.append(
        Match(gestureID: gesture.id, score: score, threshold: template.threshold)
      )
    }

    return candidates.sorted {
      let left = $0.score / $0.threshold
      let right = $1.score / $1.threshold
      if left != right { return left < right }
      return $0.gestureID.uuidString < $1.gestureID.uuidString
    }.first
  }
}

final class TemporalGestureGate {
  private var candidateID: UUID?
  private var candidateScores: [Double] = []
  private var unmatchedFrames = 0
  private var lastTriggeredID: UUID?
  private var lastTriggeredAt = Date.distantPast
  private var requiresRelease = false

  func consume(
    _ match: DeterministicGestureMatcher.Match?,
    requiredFrames: Int,
    cooldown: TimeInterval,
    now: Date = Date()
  ) -> UUID? {
    guard let match else {
      unmatchedFrames += 1
      if unmatchedFrames >= 3 {
        candidateID = nil
        candidateScores.removeAll(keepingCapacity: true)
        requiresRelease = false
      }
      return nil
    }
    unmatchedFrames = 0

    if candidateID != match.gestureID {
      candidateID = match.gestureID
      candidateScores = [match.score]
    } else {
      candidateScores.append(match.score)
      if candidateScores.count > requiredFrames { candidateScores.removeFirst() }
    }

    guard candidateScores.count >= requiredFrames else { return nil }
    let average = candidateScores.reduce(0, +) / Double(candidateScores.count)
    guard average <= match.threshold else { return nil }
    guard now.timeIntervalSince(lastTriggeredAt) >= cooldown else { return nil }
    if requiresRelease, lastTriggeredID == match.gestureID { return nil }

    lastTriggeredID = match.gestureID
    lastTriggeredAt = now
    requiresRelease = true
    candidateScores.removeAll(keepingCapacity: true)
    return match.gestureID
  }

  func reset() {
    candidateID = nil
    candidateScores.removeAll()
    unmatchedFrames = 0
    lastTriggeredID = nil
    lastTriggeredAt = .distantPast
    requiresRelease = false
  }
}

enum GestureRecordingError: LocalizedError {
  case insufficientStableSamples
  case inconsistentSamples

  var errorDescription: String? {
    switch self {
    case .insufficientStableSamples: "Not enough stable samples were collected."
    case .inconsistentSamples:
      "The captured samples were too inconsistent. Please hold the gesture steady and try again."
    }
  }
}
