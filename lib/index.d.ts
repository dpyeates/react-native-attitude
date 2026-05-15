import { type AttitudePayload } from './NativeRNAttitude';
export type { AttitudePayload };
export type OutputMode = 'both' | 'attitude' | 'heading';
export type RotationMode = 'none' | 'left' | 'right';
type WatchCallback = (payload: AttitudePayload) => void;
declare const Attitude: {
    watch(success: WatchCallback): number;
    clearWatch(watchID: number): void;
    stopObserving(): void;
    zero(): void;
    reset(): void;
    isSupported(): Promise<boolean>;
    setOutput(output: OutputMode): void;
    setInterval(interval: number): void;
    setRotation(rotation: RotationMode): void;
};
export default Attitude;
