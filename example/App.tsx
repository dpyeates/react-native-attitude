import React, { useEffect, useRef, useState } from 'react';
import { Pressable, StatusBar, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import Attitude, { type AttitudePayload, type UpdateRateHz } from 'react-native-attitude';

const DEFAULT_RATE_HZ: UpdateRateHz = 5;
const PITCH_PX_PER_DEG = 4;

const RATES: { label: string; hz: UpdateRateHz }[] = [
  { label: '1 Hz', hz: 1 },
  { label: '5 Hz', hz: 5 },
  { label: '10 Hz', hz: 10 },
  { label: '20 Hz', hz: 20 },
  { label: '40 Hz', hz: 40 },
];

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
  const [data, setData] = useState(INITIAL);
  const [rateHz, setRateHz] = useState<UpdateRateHz>(DEFAULT_RATE_HZ);
  const watchId = useRef<number | null>(null);

  useEffect(() => {
    Attitude.setOutput('both');
    Attitude.setRotation('none');
    Attitude.setInterval(rateHz);
    void Attitude.isSupported().then(setSupported);

    watchId.current = Attitude.watch(setData);

    return () => {
      if (watchId.current != null) {
        Attitude.clearWatch(watchId.current);
      }
      Attitude.stopObserving();
    };
  }, []);

  useEffect(() => {
    Attitude.setInterval(rateHz);
  }, [rateHz]);

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
        <StatusBar barStyle="dark-content" />
        <View style={styles.content}>
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
        </View>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: '#f1f5f9',
  },
  content: {
    flex: 1,
    padding: 16,
    gap: 16,
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
  chipLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: '#334155',
  },
  chipLabelSelected: {
    color: '#fff',
  },
});
