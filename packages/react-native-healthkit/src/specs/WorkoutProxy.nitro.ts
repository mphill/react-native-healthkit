import type { HybridObject } from 'react-native-nitro-modules'
import type {
  LocationForSaving,
  WorkoutEffortScore,
  WorkoutPlan,
  WorkoutRoute,
  WorkoutSample,
} from '../types/Workouts'

export interface WorkoutProxy
  extends HybridObject<{ ios: 'swift' }>,
    WorkoutSample {
  toJSON(key?: string): WorkoutSample
  saveWorkoutRoute(locations: readonly LocationForSaving[]): Promise<boolean>
  getWorkoutPlan(): Promise<WorkoutPlan | null>
  getWorkoutRoutes(): Promise<readonly WorkoutRoute[]>

  /**
   * Get the workout effort score for this workout (iOS 18+)
   * @returns Promise<number | null> - The effort score (1-10) or null if not set
   * @since iOS 18.0
   */
  getWorkoutEffortScore(): Promise<WorkoutEffortScore | null>

  /**
   * Set the workout effort score for this workout (iOS 18+)
   * @param score - The effort score to set (must be between 1 and 10)
   * @returns Promise<boolean> - True if successful
   * @since iOS 18.0
   */
  setWorkoutEffortScore(score: number): Promise<boolean>

  // nice to have here: getAllStatistics and getStatisticsForQuantityType
}
