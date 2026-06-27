import { type AttitudePayload } from './NativeRNAttitude';
export type { AttitudePayload };
export type OutputMode = 'both' | 'attitude' | 'heading';
export type RotationMode = 'none' | 'left' | 'right';
export type UpdateRateHz = 1 | 5 | 10 | 20 | 40;
type WatchCallback = (payload: AttitudePayload) => void;
declare const Attitude: {
    watch(success: WatchCallback): number;
    clearWatch(watchID: number): void;
    stopObserving(): void;
    zero(): void;
    reset(): void;
    isSupported(): Promise<boolean>;
    setOutput(output: OutputMode): void;
    setInterval(rateHz: UpdateRateHz): void;
    setRotation(rotation: RotationMode): void;
};
export default Attitude;
