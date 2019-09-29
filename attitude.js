'use strict';
import {NativeEventEmitter, NativeModules} from 'react-native';

const {RNAttitude} = NativeModules;

const AttitudeEventEmitter = new NativeEventEmitter(RNAttitude);

// the following arrays contain the subscription listeners for
// all the attitude and heading watchers.
let attitudeSubscriptions = [];

// the following '*UpdateEnabled' flags indicate if we have requested
// the relevant updates (attitude, heading) from the native side
let attitudeUpdatesEnabled = false;

const Attitude = {
  
  // Starts watching/observing of attitude
  // The success function is called upon every change
  watch: function(success) {
    if (!attitudeUpdatesEnabled) {
      RNAttitude.startObserving();
      attitudeUpdatesEnabled = true;
    }
    const watchID = attitudeSubscriptions.length;
    attitudeSubscriptions.push(AttitudeEventEmitter.addListener('attitudeDidChange', success));
    return watchID;
  },

  // Stops all watching/observing of the passed in watch ID
  clearWatch: function(watchID) {
    const sub = attitudeSubscriptions[watchID];
    if (!sub) {
      // Silently exit when the watchID is invalid or already cleared
      return;
    }
    sub.remove(); // removes the listener
    attitudeSubscriptions[watchID] = undefined;
    // check for any remaining watchers
    let noWatchers = true;
    for (let ii = 0; ii < attitudeSubscriptions.length; ii++) {
      if (attitudeSubscriptions[ii]) {
        noWatchers = false; // still valid watchers
      }
    }
    if (noWatchers) {
      RNAttitude.stopObserving();
      attitudeUpdatesEnabled = false;
    }
  },

  // Stop all watching/observing
  stopObserving: function() {
    let ii = 0;
    RNAttitude.stopObserving();
    for (ii = 0; ii < attitudeSubscriptions.length; ii++) {
      const sub = attitudeSubscriptions[ii];
      if (sub) {
        sub.remove();
      }
    }
    attitudeSubscriptions = [];
    attitudeUpdatesEnabled = false;
  },

  // Zeros the baseline attitude based on our current attitude
  zero: function() {
    RNAttitude.zero();
  },

  // Resets the attitude reference
  reset: function() {
    RNAttitude.reset();
  },
};

export default Attitude;
