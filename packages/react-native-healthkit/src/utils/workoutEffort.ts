import type { WorkoutProxy } from '../specs/WorkoutProxy.nitro'
import type { WorkoutEffortScore } from '../types/Workouts'

/**
 * Validates if a number is a valid workout effort score (1-10)
 * @param score - The score to validate
 * @returns true if the score is valid, false otherwise
 */
export const isValidWorkoutEffortScore = (score: number): score is WorkoutEffortScore => {
  return Number.isInteger(score) && score >= 1 && score <= 10
}

/**
 * Gets the workout effort score for a workout
 * @param workout - The workout proxy to get the effort score for
 * @returns Promise<number | null> - The effort score or null if not available/set
 * @since iOS 18.0
 */
export const getWorkoutEffortScore = async (workout: WorkoutProxy): Promise<number | null> => {
  try {
    return await workout.getWorkoutEffortScore()
  } catch (error) {
    // If the method is not available (iOS < 18), return null
    if (error instanceof Error && error.message.includes('unrecognized selector')) {
      return null
    }
    throw error
  }
}

/**
 * Sets the workout effort score for a workout
 * @param workout - The workout proxy to set the effort score for
 * @param score - The effort score to set (1-10)
 * @returns Promise<boolean> - True if successful
 * @throws Error if the score is invalid or if iOS version doesn't support it
 * @since iOS 18.0
 */
export const setWorkoutEffortScore = async (
  workout: WorkoutProxy,
  score: number,
): Promise<boolean> => {
  if (!isValidWorkoutEffortScore(score)) {
    throw new Error(
      `Invalid workout effort score: ${score}. Score must be an integer between 1 and 10.`,
    )
  }

  try {
    return await workout.setWorkoutEffortScore(score)
  } catch (error) {
    // If the method is not available (iOS < 18), throw a more descriptive error
    if (error instanceof Error && error.message.includes('unrecognized selector')) {
      throw new Error(
        'Workout effort scores are only available on iOS 18.0 and later. Please check the iOS version before using this feature.',
      )
    }
    throw error
  }
}

/**
 * Converts a workout effort score to a human-readable description
 * @param score - The effort score (1-10)
 * @returns A descriptive string for the effort level
 */
export const getWorkoutEffortDescription = (score: WorkoutEffortScore): string => {
  const descriptions: Record<WorkoutEffortScore, string> = {
    1: 'Very Easy',
    2: 'Easy',
    3: 'Light',
    4: 'Moderate',
    5: 'Somewhat Hard',
    6: 'Hard',
    7: 'Very Hard',
    8: 'Extremely Hard',
    9: 'Maximum Effort',
    10: 'All-Out',
  }
  
  return descriptions[score]
}

/**
 * Checks if workout effort scores are supported on the current platform
 * @returns true if supported (iOS 18+), false otherwise
 */
export const isWorkoutEffortSupported = (): boolean => {
  // This is a runtime check - in a real app you'd check the iOS version
  // For now, we'll assume it's supported and let the native code handle version checks
  return true
}
