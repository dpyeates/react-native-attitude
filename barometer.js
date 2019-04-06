'use strict';
import {NativeEventEmitter, NativeModules} from 'react-native';

const {RNBarometer} = NativeModules;

const BarometerEventEmitter = new NativeEventEmitter(RNBarometer);

let altitudeSubscriptions = [];

// the following flag indicates if we have requested altitude updates from the native side
let altitudeUpdatesEnabled = false;

const Barometer = {

  // Starts watching/observing of barometer/altitude
  // The success function is called upon every change
  watch: function(success: Function): number {
    if (!altitudeUpdatesEnabled) {
      RNBarometer.startObserving();
      altitudeUpdatesEnabled = true;
    }
    const watchID = altitudeSubscriptions.length;
    altitudeSubscriptions.push(BarometerEventEmitter.addListener('barometerUpdate', success));
    return watchID;
  },

  // Stops all watching/observing of the passed in watch ID
  clearWatch: function(watchID: number): void {
    const sub = altitudeSubscriptions[watchID];
    if (!sub) {
      // Silently exit when the watchID is invalid or already cleared
      return;
    }
    sub.remove(); // removes the listener
    altitudeSubscriptions[watchID] = undefined;
    // check for any remaining watchers
    let noWatchers = true;
    for (let ii = 0; ii < altitudeSubscriptions.length; ii++) {
      if (altitudeSubscriptions[ii]) {
        noWatchers = false; // still valid watchers
      }
    }
    if (noWatchers) {
      RNBarometer.stopObserving();
      altitudeUpdatesEnabled = false;
    }
  },

  // Stop all watching/observing
  stopObserving: function(): void {
    for (let ii = 0; ii < altitudeSubscriptions.length; ii++) {
      const sub = altitudeSubscriptions[ii];
      if (sub) {
        sub.remove();
      }
    }
    altitudeSubscriptions = [];
    altitudeUpdatesEnabled = false;
  },

  // Lets us know if this device has barometer capability or not
  isAvailable: async function() {
    return await RNBarometer.isAvailable();
  }

};

export default Barometer;
