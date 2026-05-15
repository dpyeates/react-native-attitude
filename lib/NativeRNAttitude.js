"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getNativeRNAttitude = getNativeRNAttitude;
const react_native_1 = require("react-native");
/** Resolve lazily — top-level getEnforcing breaks AppRegistry when Turbo runtime is not ready yet. */
function getNativeRNAttitude() {
    return react_native_1.TurboModuleRegistry.getEnforcing('RNAttitude');
}
