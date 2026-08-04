import type { CodegenTypes, TurboModule } from 'react-native';
export type AttitudePayload = {
    timestamp: number;
    roll: number;
    pitch: number;
    heading: number;
};
export type MotionSensorInfo = {
    id: string;
    name: string;
    vendor: string;
    version: number;
    maxRange: number;
    resolution: number;
    minDelayUs: number;
};
export interface Spec extends TurboModule {
    readonly onAttitudeUpdate: CodegenTypes.EventEmitter<AttitudePayload>;
    zero(): void;
    reset(): void;
    setOutput(output: string): void;
    setInterval(interval: number): void;
    setRotation(rotation: string): void;
    startObserving(): void;
    stopObserving(): void;
    isSupported(): Promise<boolean>;
    getAvailableSensors(): Promise<ReadonlyArray<MotionSensorInfo>>;
    isMotionAuthorizationGranted(): Promise<boolean>;
    requestMotionAuthorization(): Promise<boolean>;
    addListener(eventName: string): void;
    removeListeners(count: number): void;
}
/** Resolve lazily — top-level getEnforcing breaks AppRegistry when Turbo runtime is not ready yet. */
export declare function getNativeRNAttitude(): Spec;
