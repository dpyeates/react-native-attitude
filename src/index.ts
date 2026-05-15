import type { EventSubscription } from 'react-native';

import {
  getNativeRNAttitude,
  type AttitudePayload,
} from './NativeRNAttitude';

export type { AttitudePayload };
export type OutputMode = 'both' | 'attitude' | 'heading';
export type RotationMode = 'none' | 'left' | 'right';

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

  setOutput(output: OutputMode): void {
    getNativeModule().setOutput(output);
  },

  setInterval(interval: number): void {
    getNativeModule().setInterval(interval);
  },

  setRotation(rotation: RotationMode): void {
    getNativeModule().setRotation(rotation);
  },
};

export default Attitude;
