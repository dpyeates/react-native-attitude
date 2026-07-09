import type { EventSubscription } from 'react-native';

import {
  getNativeRNAttitude,
  type AttitudePayload,
  type MotionSensorInfo,
} from './NativeRNAttitude';

export type { AttitudePayload, MotionSensorInfo };
export type OutputMode = 'both' | 'attitude' | 'heading';
export type RotationMode = 'none' | 'left' | 'right';
export type UpdateRateHz = 1 | 5 | 10 | 20 | 40;

const RATE_MS: Record<UpdateRateHz, number> = {
  1: 1000,
  5: 200,
  10: 100,
  20: 50,
  40: 25,
};

type WatchCallback = (payload: AttitudePayload) => void;

let watchIdCounter = 0;
const subscriptions = new Map<number, EventSubscription>();
let observing = false;

function getNativeModule() {
  return getNativeRNAttitude();
}

const Attitude = {
  watch(success: WatchCallback): number {
    const native = getNativeModule();
    if (!observing) {
      native.startObserving();
      observing = true;
    }
    const watchID = watchIdCounter++;
    const subscription = native.onAttitudeUpdate(success);
    subscriptions.set(watchID, subscription);
    return watchID;
  },

  clearWatch(watchID: number): void {
    const subscription = subscriptions.get(watchID);
    if (subscription == null) {
      return;
    }
    subscription.remove();
    subscriptions.delete(watchID);
    if (subscriptions.size === 0 && observing) {
      getNativeModule().stopObserving();
      observing = false;
    }
  },

  stopObserving(): void {
    if (observing) {
      getNativeModule().stopObserving();
      observing = false;
    }
    for (const subscription of subscriptions.values()) {
      subscription.remove();
    }
    subscriptions.clear();
  },

  zero(): void {
    getNativeModule().zero();
  },

  reset(): void {
    getNativeModule().reset();
  },

  async isSupported(): Promise<boolean> {
    return getNativeModule().isSupported();
  },

  async getAvailableSensors(): Promise<MotionSensorInfo[]> {
    return getNativeModule().getAvailableSensors() as Promise<MotionSensorInfo[]>;
  },

  setOutput(output: OutputMode): void {
    getNativeModule().setOutput(output);
  },

  setInterval(rateHz: UpdateRateHz): void {
    getNativeModule().setInterval(RATE_MS[rateHz]);
  },

  setRotation(rotation: RotationMode): void {
    getNativeModule().setRotation(rotation);
  },
};

export default Attitude;
