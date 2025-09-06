//
//  WorkoutProxy.swift
//  Pods
//
//  Created by Robert Herber on 2025-06-07.
//

import CoreLocation
import HealthKit
import NitroModules

@available(iOS 17.0.0, *)
func getWorkoutPlanInternal(workout: HKWorkout) async throws -> WorkoutPlan? {
  let workoutPlan = try await workout.workoutPlan
  if let id = workoutPlan?.id.uuidString {
    if let activityType = workoutPlan?.workout.activity {
      let workoutPlan = WorkoutPlan(
        id: id,
        activityType: WorkoutActivityType.init(
          rawValue: Int32(activityType.rawValue)
        )!
      )

      return workoutPlan
    }
  }

  return nil
}

func getWorkoutRoutesInternal(
  workout: HKWorkout
) async throws -> [HKWorkoutRoute]? {
  let workoutPredicate = HKQuery.predicateForObjects(from: workout)
  let samples = try await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<[HKSample], Error>) in
    let query = HKAnchoredObjectQuery(
      type: HKSeriesType.workoutRoute(),
      predicate: workoutPredicate,
      anchor: nil,
      limit: HKObjectQueryNoLimit
    ) {
      (_, samples, _, _, error) in

      if let hasError = error {
        return continuation.resume(throwing: hasError)

      }

      guard let samples = samples else {
        return continuation.resume(
          throwing: RuntimeError.error(withMessage: "Empty response")
        )
      }

      continuation.resume(returning: samples)
    }
    store.execute(query)
  }

  guard let routes = samples as? [HKWorkoutRoute] else {
    return nil
  }

  return routes
}

func getRouteLocations(
  route: HKWorkoutRoute
) async -> [CLLocation] {
  let locations = try! await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<[CLLocation], Error>) in
    var allLocations: [CLLocation] = []

    let query = HKWorkoutRouteQuery(route: route) {
      (_, locationsOrNil, done, errorOrNil) in

      if let error = errorOrNil {
        continuation.resume(throwing: error)
        return
      }

      guard let currentLocationBatch = locationsOrNil else {
        return continuation.resume(
          throwing: RuntimeError.error(withMessage: "Empty response")
        )
      }

      allLocations.append(contentsOf: currentLocationBatch)

      if done {
        continuation.resume(returning: allLocations)
      }
    }

    store.execute(query)
  }

  return locations
}

func serializeLocation(location: CLLocation, previousLocation: CLLocation?)
  -> WorkoutRouteLocation {
  var distance: CLLocationDistance?
  if let previousLocation = previousLocation {
    distance = location.distance(from: previousLocation)
  } else {
    distance = nil
  }

  return WorkoutRouteLocation(
    altitude: location.altitude,
    course: location.course,
    date: location.timestamp,
    distance: distance,
    horizontalAccuracy: location.horizontalAccuracy,
    latitude: location.coordinate.latitude,
    longitude: location.coordinate.longitude,
    speed: location.speed,
    speedAccuracy: location.speedAccuracy,
    verticalAccuracy: location.verticalAccuracy
  )
}

func getSerializedWorkoutLocations(
  workout: HKWorkout
) async throws -> [WorkoutRoute] {
  let routes = try await getWorkoutRoutesInternal(
    workout: workout
  )

  var allRoutes: [WorkoutRoute] = []
  guard let _routes = routes else {
    throw RuntimeError.error(withMessage: "Unexpected empty response")
  }
  for route in _routes {
    let routeMetadata = serializeMetadata(
      route.metadata
    )

    let routeCLLocations = await getRouteLocations(
      route: route
    )

    let routeLocations = routeCLLocations.enumerated().map {
      (i, loc) in
      serializeLocation(
        location: loc,
        previousLocation: i == 0 ? nil : routeCLLocations[i - 1]
      )
    }
    // let routeInfos: WorkoutRoute = ["locations": routeLocations]

    allRoutes.append(
      WorkoutRoute(
        locations: routeLocations,
        HKMetadataKeySyncIdentifier: routeMetadata.getString(
          key: "HKMetadataKeySyncIdentifier"
        ),
        HKMetadataKeySyncVersion: routeMetadata.getDouble(
          key: "HKMetadataKeySyncVersion"
        )
      )
    )
  }
  return allRoutes
}

func saveWorkoutRouteInternal(
  workout: HKWorkout,
  locations: [LocationForSaving]
) -> Promise<Bool> {
  return Promise.async {
    try await withCheckedThrowingContinuation { continuation in
      Task {
        do {
          // create CLLocations and return if locations are empty
          let clLocations = mapLocations(from: locations)
          let routeBuilder = HKWorkoutRouteBuilder(
            healthStore: store,
            device: nil
          )
          try await routeBuilder.insertRouteData(clLocations)
          try await routeBuilder.finishRoute(with: workout, metadata: nil)

          return continuation.resume(returning: true)
        } catch {
          return continuation.resume(throwing: error)
        }
      }

    }
  }
}

@available(iOS 18.0, *)
func getWorkoutEffortScoreInternal(workout: HKWorkout) async throws -> Double? {
  let sampleType = HKQuantityType(.workoutEffortScore)
  let predicate = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
  let descriptor = HKSampleQueryDescriptor(predicates: [
    HKSamplePredicate.sample(type: sampleType, predicate: predicate)
  ], sortDescriptors: [])

  let samples = try await descriptor.result(for: store)

  if let lastSample = samples.last as? HKQuantitySample {
    let doubleValue = lastSample.quantity.doubleValue(for: .appleEffortScore())
    return doubleValue
  } else {
    return nil
  }
}

@available(iOS 18.0, *)
func setWorkoutEffortScoreInternal(workout: HKWorkout, score: Double) async throws -> Bool {
  // Validate score is between 1 and 10
  guard score >= 1.0 && score <= 10.0 else {
    throw RuntimeError.error(withMessage: "[react-native-healthkit] Workout effort score must be between 1 and 10, got: \(score)")
  }

  let sampleType = HKQuantityType(.workoutEffortScore)
  let predicate = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
  let descriptor = HKSampleQueryDescriptor(predicates: [
    HKSamplePredicate.sample(type: sampleType, predicate: predicate)
  ], sortDescriptors: [])

  // Delete existing effort records created by this app
  for sample in try await descriptor.result(for: store) {
    // May not delete all records: only app-created entries can be deleted
    try? await store.delete(sample)
  }

  // Create new effort score sample
  let effort = HKQuantitySample(
    type: sampleType,
    quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: score),
    start: workout.startDate,
    end: workout.endDate
  )

  // Relate the effort score to the workout
  try await store.relateWorkoutEffortSample(effort, with: workout, activity: nil)

  return true
}

class WorkoutProxy: HybridWorkoutProxySpec {
  func toJSON(key: String?) throws -> WorkoutSample {
    if key != nil && key?.isEmpty != true {
      print("WorkoutProxy does not support toJSON with key: \(key!)")
    }

    return WorkoutSample(
      uuid: self.uuid,
      device: self.device,
      workoutActivityType: self.workoutActivityType,
      duration: self.duration,
      totalDistance: self.totalDistance,
      totalEnergyBurned: self.totalEnergyBurned,
      totalSwimmingStrokeCount: self.totalSwimmingStrokeCount,
      totalFlightsClimbed: self.totalFlightsClimbed,
      startDate: self.startDate,
      endDate: self.endDate,
      metadata: self.metadata,
      sourceRevision: self.sourceRevision,
      events: self.events,
      activities: self.activities
    )
  }

  var workoutPredicate: NSPredicate {
    get {
      let predicate = HKQuery.predicateForObjects(from: self.workout)
      return predicate
    }
  }

  var uuid: String {
    get {
      return workout.uuid.uuidString
    }
  }

  var device: Device? {
    if let hkDevice = workout.device {
      return Device(
        name: hkDevice.name,
        firmwareVersion: hkDevice.firmwareVersion,
        hardwareVersion: hkDevice.hardwareVersion,
        localIdentifier: hkDevice.localIdentifier,
        manufacturer: hkDevice.manufacturer,
        model: hkDevice.model,
        softwareVersion: hkDevice.softwareVersion,
        udiDeviceIdentifier: hkDevice.udiDeviceIdentifier
      )
    }
    return nil
  }

  var workoutActivityType: WorkoutActivityType {
    get {
      if let activityType = WorkoutActivityType.init(
        rawValue: Int32(workout.workoutActivityType.rawValue)
      ) {
        return activityType
      }

      print("Unknown workout activity type: \(workout.workoutActivityType.rawValue), falling back to 'other'")

      return WorkoutActivityType.other
    }
  }

  var duration: Quantity {
    get {
      let quantity = HKQuantity(unit: .second(), doubleValue: workout.duration)

      let duration = serializeQuantityTyped(
        unit: .second(),
        quantity: quantity
      )

      return duration
    }
  }

  var totalDistance: Quantity? {
    if let hkTotalDistance = workout.totalDistance {
      return Quantity(
        unit: "meters",
        quantity: hkTotalDistance.doubleValue(for: HKUnit.meter())
      )
    }
    return nil
  }

  var totalEnergyBurned: Quantity? {
    get {
      return serializeQuantityTyped(
        unit: energyUnit,
        quantityNullable: workout.totalEnergyBurned
      )
    }
  }

  var totalSwimmingStrokeCount: Quantity? {
    get {
    return serializeQuantityTyped(
      unit: .count(),
      quantityNullable: workout.totalSwimmingStrokeCount
    )
    }

  }

  var totalFlightsClimbed: Quantity? {
    if #available(iOS 11, *) {
      if let hkTotalFlightsClimbed = workout.totalFlightsClimbed {
        return Quantity(
          unit: "count",
          quantity: hkTotalFlightsClimbed.doubleValue(for: HKUnit.count())
        )
      }
    }
    return nil
  }

  var energyUnit: HKUnit

  var startDate: Date {
    get {
      return workout.startDate
    }
  }

  var endDate: Date {
    get {
      return workout.endDate
    }
  }

  var metadata: AnyMap? {
    get {
      return serializeMetadata(workout.metadata)
    }
  }

  var sourceRevision: SourceRevision? {
    get {
      return serializeSourceRevision(workout.sourceRevision)
    }
  }

  var events: [WorkoutEvent]? {
    if let hkWorkoutEvents = workout.workoutEvents {
      return hkWorkoutEvents.compactMap { event in
        if let type = WorkoutEventType.init(
          rawValue: Int32(event.type.rawValue)
        ) {
          return WorkoutEvent(
            type: type,
            startDate: event.dateInterval.start,
            endDate: event.dateInterval.end
          )
        }
        print(
          "Failed to initialize WorkoutEventType with rawValue: \(event.type.rawValue)"
        )
        return nil
      }
    }
    return nil
  }

  var activities: [WorkoutActivity]? {
    if #available(iOS 16.0, *) {
      let hkActivities = workout.workoutActivities

      return hkActivities.map { activity in
        return WorkoutActivity(
          startDate: activity.startDate,
          endDate: activity.endDate ?? activity.startDate,
          uuid: activity.uuid.uuidString,
          duration: activity.duration
        )
      }
    }
    return nil
  }

  let distanceUnit: HKUnit

  private let workout: HKWorkout

  init(workout: HKWorkout, distanceUnit: HKUnit, energyUnit: HKUnit) {
    self.energyUnit = energyUnit
    self.distanceUnit = distanceUnit

    self.workout = workout
  }

  func getWorkoutPlan() throws -> Promise<WorkoutPlan?> {
    return Promise.async {
      if #available(iOS 17.0.0, *) {
        return try await getWorkoutPlanInternal(workout: self.workout)
      } else {
        throw RuntimeError.error(
          withMessage: "Workout plans are only available on iOS 17.0 or later"
        )
      }
    }
  }

  func saveWorkoutRoute(locations: [LocationForSaving]) throws -> Promise<Bool> {
    return saveWorkoutRouteInternal(workout: self.workout, locations: locations)
  }

  func getWorkoutRoutes() throws -> Promise<[WorkoutRoute]> {
    return Promise.async {
      return try await getSerializedWorkoutLocations(workout: self.workout)
    }
  }

  @available(iOS 18.0, *)
  func getWorkoutEffortScore() throws -> Promise<Double?> {
    return Promise.async {
      return try await getWorkoutEffortScoreInternal(workout: self.workout)
    }
  }

  @available(iOS 18.0, *)
  func setWorkoutEffortScore(score: Double) throws -> Promise<Bool> {
    return Promise.async {
      return try await setWorkoutEffortScoreInternal(workout: self.workout, score: score)
    }
  }
}
