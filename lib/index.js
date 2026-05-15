"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const NativeRNAttitude_1 = require("./NativeRNAttitude");
let watchIdCounter = 0;
const subscriptions = new Map();
let observing = false;
function getNativeModule() {
    return (0, NativeRNAttitude_1.getNativeRNAttitude)();
}
const Attitude = {
    watch(success) {
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
    clearWatch(watchID) {
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
    stopObserving() {
        if (observing) {
            getNativeModule().stopObserving();
            observing = false;
        }
        for (const subscription of subscriptions.values()) {
            subscription.remove();
        }
        subscriptions.clear();
    },
    zero() {
        getNativeModule().zero();
    },
    reset() {
        getNativeModule().reset();
    },
    async isSupported() {
        return getNativeModule().isSupported();
    },
    setOutput(output) {
        getNativeModule().setOutput(output);
    },
    setInterval(interval) {
        getNativeModule().setInterval(interval);
    },
    setRotation(rotation) {
        getNativeModule().setRotation(rotation);
    },
};
exports.default = Attitude;
