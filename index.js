'use strict';
import {NativeEventEmitter, NativeModules} from 'react-native';

const {RNAttitude} = NativeModules;

const AttitudeEventEmitter = new NativeEventEmitter(RNAttitude);

// the following arrays contain the subscription listeners for
//  all the attitude, heading and altitude watchers.
let attitudeSubscriptions = [];
let headingSubscriptions = [];
let altitudeSubscriptions = [];

// the following '*UpdateEnabled' flags indicate if we have requested
// the relevent updates (attitude, heading or altitude) from the native side
let attitudeUpdatesEnabled = false;
let headingUpdatesEnabled = false;
let altitudeUpdatesEnabled = false;

const Attitude = {
  // Starts watching/observing of attitude
  // The success function is called upon every change
  watchAttitude: function(success: Function): number {
    if (!attitudeUpdatesEnabled) {
      RNAttitude.startObservingAttitude();
      attitudeUpdatesEnabled = true;
    }
    const watchID = attitudeSubscriptions.length;
    attitudeSubscriptions.push(AttitudeEventEmitter.addListener('attitudeDidChange', success));
    return watchID;
  },

  // Starts watching/observing of heading
  // The success function is called upon every change
  watchHeading: function(success: Function): number {
    if (!headingUpdatesEnabled) {
      RNAttitude.startObservingHeading();
      headingUpdatesEnabled = true;
    }
    const watchID = headingSubscriptions.length;
    headingSubscriptions.push(AttitudeEventEmitter.addListener('headingDidChange', success));
    return watchID;
  },

  // Starts watching/observing of altitude
  // The success function is called upon every change
  watchAltitude: function(success: Function): number {
    if (!altitudeUpdatesEnabled) {
      RNAttitude.startObservingAltitude();
      altitudeUpdatesEnabled = true;
    }
    const watchID = altitudeSubscriptions.length;
    altitudeSubscriptions.push(AttitudeEventEmitter.addListener('altitudeDidChange', success));
    return watchID;
  },

  // Stops all watching/observing of the passed in watch ID
  clearWatchAttitude: function(watchID: number): void {
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
      RNAttitude.stopObservingAttitude();
      attitudeUpdatesEnabled = false;
    }
  },

  // Stops all watching/observing of the passed in watch ID
  clearWatchHeading: function(watchID: number): void {
    const sub = headingSubscriptions[watchID];
    if (!sub) {
      // Silently exit when the watchID is invalid or already cleared
      return;
    }
    sub.remove(); // removes the listener
    headingSubscriptions[watchID] = undefined;
    // check for any remaining watchers
    let noWatchers = true;
    for (let ii = 0; ii < headingSubscriptions.length; ii++) {
      if (headingSubscriptions[ii]) {
        noWatchers = false; // still valid watchers
      }
    }
    if (noWatchers) {
      RNAttitude.stopObservingHeading();
      headingUpdatesEnabled = false;
    }
  },

  // Stops all watching/observing of the passed in watch ID
  clearWatchAltitude: function(watchID: number): void {
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
      RNAttitude.stopObservingAltitude();
      altitudeUpdatesEnabled = false;
    }
  },

  // Stop all watching/observing of both attitude and heading
  stopObserving: function(): void {
    let ii = 0;
    RNAttitude.stopObserving();
    for (ii = 0; ii < attitudeSubscriptions.length; ii++) {
      const sub = attitudeSubscriptions[ii];
      if (sub) {
        sub.remove();
      }
    }
    attitudeSubscriptions = [];
    for (ii = 0; ii < headingSubscriptions.length; ii++) {
      const sub = headingSubscriptions[ii];
      if (sub) {
        sub.remove();
      }
    }
    headingSubscriptions = [];
    for (ii = 0; ii < altitudeSubscriptions.length; ii++) {
      const sub = altitudeSubscriptions[ii];
      if (sub) {
        sub.remove();
      }
    }
    altitudeSubscriptions = [];
    attitudeUpdatesEnabled = false;
    headingUpdatesEnabled = false;
    altitudeUpdatesEnabled = false;
  },

  // Zeros our attitude based on our current attitude
  zero: function(): void {
    RNAttitude.zero();
  },

  // Resets our attitude reference
  reset: function(): void {
    RNAttitude.reset();
  },

  // Lets us know if this device has barometer capability or not
  hasBarometer: async function() {
    const result = await RNAttitude.hasBarometer();
    return result;
  }
};

export default Attitude;
