import React, { useState, useEffect } from 'react';
import { View, Text, Button, Alert, StyleSheet } from 'react-native';
import {
  requestAuthorization,
  getMostRecentWorkout,
  WorkoutEffortUtils,
  type WorkoutProxy,
} from '@kingstinct/react-native-healthkit';

/**
 * Example component demonstrating workout effort score functionality
 * Requires iOS 18+ to function properly
 */
export const WorkoutEffortExample: React.FC = () => {
  const [workout, setWorkout] = useState<WorkoutProxy | null>(null);
  const [effortScore, setEffortScore] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [hasPermissions, setHasPermissions] = useState(false);

  // Request permissions on component mount
  useEffect(() => {
    const requestPermissions = async () => {
      try {
        await requestAuthorization(
          ['HKQuantityTypeIdentifierWorkoutEffortScore', 'HKWorkoutTypeIdentifier'],
          ['HKQuantityTypeIdentifierWorkoutEffortScore']
        );
        setHasPermissions(true);
      } catch (error) {
        console.error('Failed to request permissions:', error);
        Alert.alert('Permission Error', 'Failed to request HealthKit permissions');
      }
    };

    requestPermissions();
  }, []);

  // Load the most recent workout
  const loadMostRecentWorkout = async () => {
    if (!hasPermissions) {
      Alert.alert('Error', 'HealthKit permissions not granted');
      return;
    }

    setLoading(true);
    try {
      const recentWorkout = await getMostRecentWorkout();
      if (recentWorkout) {
        setWorkout(recentWorkout);
        
        // Load existing effort score
        const existingScore = await WorkoutEffortUtils.getWorkoutEffortScore(recentWorkout);
        setEffortScore(existingScore);
      } else {
        Alert.alert('No Workouts', 'No workouts found in HealthKit');
      }
    } catch (error) {
      console.error('Failed to load workout:', error);
      Alert.alert('Error', 'Failed to load workout data');
    } finally {
      setLoading(false);
    }
  };

  // Set effort score for the current workout
  const setWorkoutEffort = async (score: number) => {
    if (!workout) {
      Alert.alert('Error', 'No workout selected');
      return;
    }

    if (!WorkoutEffortUtils.isValidWorkoutEffortScore(score)) {
      Alert.alert('Invalid Score', 'Effort score must be between 1 and 10');
      return;
    }

    setLoading(true);
    try {
      await WorkoutEffortUtils.setWorkoutEffortScore(workout, score);
      setEffortScore(score);
      Alert.alert(
        'Success', 
        `Workout effort set to ${score} (${WorkoutEffortUtils.getWorkoutEffortDescription(score as any)})`
      );
    } catch (error) {
      console.error('Failed to set effort score:', error);
      if (error instanceof Error && error.message.includes('iOS 18.0 and later')) {
        Alert.alert('iOS Version', 'Workout effort scores require iOS 18 or later');
      } else {
        Alert.alert('Error', 'Failed to set workout effort score');
      }
    } finally {
      setLoading(false);
    }
  };

  // Render effort score buttons
  const renderEffortButtons = () => {
    const scores = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    
    return (
      <View style={styles.buttonGrid}>
        {scores.map((score) => (
          <Button
            key={score}
            title={`${score}`}
            onPress={() => setWorkoutEffort(score)}
            disabled={loading}
            color={effortScore === score ? '#007AFF' : undefined}
          />
        ))}
      </View>
    );
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Workout Effort Score Example</Text>
      
      {!hasPermissions && (
        <Text style={styles.warning}>
          Requesting HealthKit permissions...
        </Text>
      )}

      <Button
        title="Load Most Recent Workout"
        onPress={loadMostRecentWorkout}
        disabled={loading || !hasPermissions}
      />

      {workout && (
        <View style={styles.workoutInfo}>
          <Text style={styles.subtitle}>Current Workout:</Text>
          <Text>Activity: {workout.workoutActivityType}</Text>
          <Text>Duration: {Math.round(workout.duration.quantity)} {workout.duration.unit}</Text>
          <Text>Start: {new Date(workout.startDate).toLocaleString()}</Text>
          
          {effortScore !== null ? (
            <View style={styles.effortInfo}>
              <Text style={styles.effortText}>
                Current Effort Score: {effortScore} ({WorkoutEffortUtils.getWorkoutEffortDescription(effortScore as any)})
              </Text>
            </View>
          ) : (
            <Text style={styles.noEffort}>No effort score set</Text>
          )}
        </View>
      )}

      {workout && (
        <View style={styles.effortSection}>
          <Text style={styles.subtitle}>Set Effort Score (1-10):</Text>
          <Text style={styles.description}>
            Rate how hard this workout felt from 1 (very easy) to 10 (all-out)
          </Text>
          {renderEffortButtons()}
        </View>
      )}

      {loading && <Text style={styles.loading}>Loading...</Text>}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 20,
    backgroundColor: '#f5f5f5',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 18,
    fontWeight: '600',
    marginTop: 20,
    marginBottom: 10,
  },
  warning: {
    color: '#ff6b35',
    textAlign: 'center',
    marginBottom: 20,
  },
  workoutInfo: {
    backgroundColor: 'white',
    padding: 15,
    borderRadius: 8,
    marginTop: 20,
  },
  effortInfo: {
    backgroundColor: '#e8f5e8',
    padding: 10,
    borderRadius: 5,
    marginTop: 10,
  },
  effortText: {
    fontWeight: '600',
    color: '#2d5a2d',
  },
  noEffort: {
    fontStyle: 'italic',
    color: '#666',
    marginTop: 10,
  },
  effortSection: {
    marginTop: 20,
  },
  description: {
    fontSize: 14,
    color: '#666',
    marginBottom: 15,
  },
  buttonGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    gap: 10,
  },
  loading: {
    textAlign: 'center',
    marginTop: 20,
    fontStyle: 'italic',
  },
});

export default WorkoutEffortExample;
