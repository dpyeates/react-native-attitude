import React, { useEffect, useRef, useState } from 'react';
import {
  Dimensions,
  Platform,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import Attitude, {
  type AttitudePayload,
  type MotionSensorInfo,
  type RotationMode,
  type UpdateRateHz,
} from 'react-native-attitude';

const DEFAULT_RATE_HZ: UpdateRateHz = 5;
const DEFAULT_ROTATION: RotationMode = 'auto';
const PITCH_PX_PER_DEG = 4;

const RATES: { label: string; hz: UpdateRateHz }[] = [
  { label: '1 Hz', hz: 1 },
  { label: '5 Hz', hz: 5 },
  { label: '10 Hz', hz: 10 },
  { label: '20 Hz', hz: 20 },
  { label: '40 Hz', hz: 40 },
];

const ROTATIONS: { label: string; mode: RotationMode }[] = [
  { label: 'None', mode: 'none' },
  { label: 'Left', mode: 'left' },
  { label: 'Right', mode: 'right' },
  { label: 'Upside down', mode: 'upsidedown' },
  { label: 'Auto', mode: 'auto' },
];

// Phones never display the interface upside down (iOS refuses to rotate to it on
// iPhones, and Android phones do not offer reverse portrait either), so only offer
// that baseline on tablets.
const UPSIDEDOWN_SUPPORTED =
  Platform.OS === 'ios'
    ? Platform.isPad
    : Math.min(
        Dimensions.get('screen').width,
        Dimensions.get('screen').height,
      ) >= 600;

const INITIAL: AttitudePayload = {
  timestamp: 0,
  roll: 0,
  pitch: 0,
  heading: 0,
};

function Horizon({ pitch, roll }: { pitch: number; roll: number }) {
  return (
    <View style={styles.horizon}>
      <View
        style={[
          styles.world,
          {
            transform: [
              { rotate: `${-roll}deg` },
              { translateY: pitch * PITCH_PX_PER_DEG },
            ],
          },
        ]}
      >
        <View style={styles.sky} />
        <View style={styles.horizonLine} />
        <View style={styles.ground} />
      </View>
      <View style={styles.crosshairH} />
      <View style={styles.crosshairV} />
    </View>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.metric}>
      <Text style={styles.metricLabel}>{label}</Text>
      <Text style={styles.metricValue}>{value}</Text>
    </View>
  );
}

export default function App() {
  const [supported, setSupported] = useState<boolean | null>(null);
  const [motionAuthorized, setMotionAuthorized] = useState<boolean | null>(null);
  const [sensors, setSensors] = useState<MotionSensorInfo[]>([]);
  const [data, setData] = useState(INITIAL);
  const [rateHz, setRateHz] = useState<UpdateRateHz>(DEFAULT_RATE_HZ);
  const [rotation, setRotation] = useState<RotationMode>(DEFAULT_ROTATION);
  const watchId = useRef<number | null>(null);

  useEffect(() => {
    let cancelled = false;

    Attitude.setOutput('both');
    Attitude.setRotation(DEFAULT_ROTATION);
    Attitude.setInterval(rateHz);

    void (async () => {
      const authorized = await Attitude.requestMotionAuthorization();
      if (cancelled) {
        return;
      }
      setMotionAuthorized(authorized);

      void Attitude.isSupported().then((value) => {
        if (!cancelled) {
          setSupported(value);
        }
      });
      void Attitude.getAvailableSensors().then((value) => {
        if (!cancelled) {
          setSensors(value);
        }
      });

      watchId.current = Attitude.watch(setData);
    })();

    return () => {
      cancelled = true;
      if (watchId.current != null) {
        Attitude.clearWatch(watchId.current);
      }
      Attitude.stopObserving();
    };
  }, []);

  useEffect(() => {
    Attitude.setInterval(rateHz);
  }, [rateHz]);

  useEffect(() => {
    Attitude.setRotation(rotation);
  }, [rotation]);

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
        <StatusBar barStyle="dark-content" />
        <ScrollView
          style={styles.scroll}
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
        >
          {motionAuthorized === false && (
            <Text style={styles.warning}>
              Motion access was denied. Enable Motion & Fitness for this app in
              Settings.
            </Text>
          )}
          {supported === false && (
            <Text style={styles.warning}>
              Attitude is not supported on this device.
            </Text>
          )}

          <Horizon pitch={data.pitch} roll={data.roll} />

          <View style={styles.card}>
            <Metric label="Roll" value={`${data.roll.toFixed(1)}°`} />
            <Metric label="Pitch" value={`${data.pitch.toFixed(1)}°`} />
            <Metric label="Heading" value={`${data.heading.toFixed(0)}°`} />
          </View>

          <View style={styles.row}>
            <Pressable style={styles.btn} onPress={() => Attitude.zero()}>
              <Text style={styles.btnLabel}>Zero</Text>
            </Pressable>
            <Pressable style={styles.btn} onPress={() => Attitude.reset()}>
              <Text style={styles.btnLabel}>Reset</Text>
            </Pressable>
          </View>

          <Text style={styles.sectionLabel}>Update rate</Text>
          <View style={styles.rateRow}>
            {RATES.map(({ label, hz }) => {
              const selected = rateHz === hz;
              return (
                <Pressable
                  key={hz}
                  style={[styles.chip, selected && styles.chipSelected]}
                  onPress={() => setRateHz(hz)}
                >
                  <Text style={[styles.chipLabel, selected && styles.chipLabelSelected]}>
                    {label}
                  </Text>
                </Pressable>
              );
            })}
          </View>

          <Text style={styles.sectionLabel}>Rotation baseline</Text>
          <View style={styles.rateRow}>
            {ROTATIONS.map(({ label, mode }) => {
              const selected = rotation === mode;
              const disabled = mode === 'upsidedown' && !UPSIDEDOWN_SUPPORTED;
              return (
                <Pressable
                  key={mode}
                  testID={`rotation-${mode}`}
                  disabled={disabled}
                  style={[
                    styles.chip,
                    selected && styles.chipSelected,
                    disabled && styles.chipDisabled,
                  ]}
                  onPress={() => setRotation(mode)}
                >
                  <Text
                    style={[
                      styles.chipLabel,
                      selected && styles.chipLabelSelected,
                      disabled && styles.chipLabelDisabled,
                    ]}
                  >
                    {label}
                  </Text>
                </Pressable>
              );
            })}
          </View>

          <Text style={styles.sectionLabel}>
            Available sensors ({sensors.length})
          </Text>
          <View style={styles.card}>
            {sensors.length === 0 ? (
              <Text style={styles.sensorEmpty}>None reported yet.</Text>
            ) : (
              sensors.map((sensor, index) => (
                <View
                  key={`${sensor.id}-${sensor.name}-${index}`}
                  style={[
                    styles.sensorRow,
                    index > 0 && styles.sensorRowBorder,
                  ]}
                >
                  <View style={styles.sensorText}>
                    <Text style={styles.sensorId}>{sensor.id}</Text>
                    <Text style={styles.sensorName}>
                      {sensor.name}
                      {sensor.vendor ? ` · ${sensor.vendor}` : ''}
                    </Text>
                  </View>
                  {sensor.minDelayUs > 0 && (
                    <Text style={styles.sensorMeta}>
                      {(1_000_000 / sensor.minDelayUs).toFixed(0)} Hz max
                    </Text>
                  )}
                </View>
              ))
            )}
          </View>
        </ScrollView>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: '#f1f5f9',
  },
  scroll: {
    flex: 1,
  },
  content: {
    padding: 16,
    gap: 16,
    flexGrow: 1,
  },
  warning: {
    color: '#b45309',
    textAlign: 'center',
    fontSize: 15,
  },
  horizon: {
    flex: 1,
    minHeight: 280,
    borderRadius: 16,
    overflow: 'hidden',
    backgroundColor: '#87ceeb',
    borderWidth: 1,
    borderColor: '#cbd5e1',
  },
  world: {
    position: 'absolute',
    width: '280%',
    height: '280%',
    left: '-90%',
    top: '-90%',
    flexDirection: 'column',
  },
  sky: {
    flex: 1,
    backgroundColor: '#87ceeb',
  },
  horizonLine: {
    height: 3,
    backgroundColor: '#ffffff',
  },
  ground: {
    flex: 1,
    backgroundColor: '#d4b896',
  },
  crosshairH: {
    position: 'absolute',
    left: '50%',
    top: '50%',
    width: 24,
    height: 2,
    marginLeft: -12,
    marginTop: -1,
    backgroundColor: '#0f172a',
  },
  crosshairV: {
    position: 'absolute',
    left: '50%',
    top: '50%',
    width: 2,
    height: 24,
    marginLeft: -1,
    marginTop: -12,
    backgroundColor: '#0f172a',
  },
  card: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    gap: 8,
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  metric: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  metricLabel: {
    color: '#64748b',
    fontSize: 16,
  },
  metricValue: {
    color: '#0f172a',
    fontSize: 22,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  row: {
    flexDirection: 'row',
    gap: 8,
  },
  btn: {
    flex: 1,
    backgroundColor: '#fff',
    paddingVertical: 12,
    borderRadius: 10,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#cbd5e1',
  },
  btnLabel: {
    color: '#0f172a',
    fontWeight: '600',
    fontSize: 16,
  },
  sectionLabel: {
    color: '#64748b',
    fontSize: 13,
    fontWeight: '600',
  },
  rateRow: {
    flexDirection: 'row',
    gap: 6,
  },
  chip: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 10,
    alignItems: 'center',
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#cbd5e1',
  },
  chipSelected: {
    backgroundColor: '#2563eb',
    borderColor: '#2563eb',
  },
  chipDisabled: {
    opacity: 0.4,
  },
  chipLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: '#334155',
  },
  chipLabelSelected: {
    color: '#fff',
  },
  chipLabelDisabled: {
    color: '#94a3b8',
  },
  sensorEmpty: {
    color: '#94a3b8',
    fontSize: 14,
  },
  sensorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingVertical: 4,
  },
  sensorRowBorder: {
    borderTopWidth: 1,
    borderTopColor: '#e2e8f0',
    paddingTop: 10,
    marginTop: 6,
  },
  sensorText: {
    flex: 1,
    gap: 2,
  },
  sensorId: {
    color: '#0f172a',
    fontSize: 15,
    fontWeight: '600',
  },
  sensorName: {
    color: '#64748b',
    fontSize: 13,
  },
  sensorMeta: {
    color: '#64748b',
    fontSize: 12,
    fontVariant: ['tabular-nums'],
  },
});
