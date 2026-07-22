/**
 * @format
 */

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';

const mockNativeAttitude = {
  onAttitudeUpdate: jest.fn(() => ({ remove: jest.fn() })),
  zero: jest.fn(),
  reset: jest.fn(),
  setOutput: jest.fn(),
  setInterval: jest.fn(),
  setRotation: jest.fn(),
  startObserving: jest.fn(),
  stopObserving: jest.fn(),
  isSupported: jest.fn(() => Promise.resolve(true)),
  getAvailableSensors: jest.fn(() => Promise.resolve([])),
  addListener: jest.fn(),
  removeListeners: jest.fn(),
};

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);

jest.mock('react-native/Libraries/TurboModule/TurboModuleRegistry', () => {
  const actual = jest.requireActual(
    'react-native/Libraries/TurboModule/TurboModuleRegistry',
  );
  return {
    ...actual,
    get: (name: string) =>
      name === 'RNAttitude' ? mockNativeAttitude : actual.get(name),
    getEnforcing: (name: string) =>
      name === 'RNAttitude' ? mockNativeAttitude : actual.getEnforcing(name),
  };
});

import App from '../App';

beforeEach(() => {
  jest.clearAllMocks();
});

test('renders correctly', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });
});

test('starts in auto rotation mode', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });
  expect(mockNativeAttitude.setRotation).toHaveBeenCalledWith('auto');
});

test.each(['none', 'left', 'right', 'auto'] as const)(
  'selecting the %s rotation chip forwards it to the native module',
  async (mode) => {
    let renderer!: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      renderer = ReactTestRenderer.create(<App />);
    });
    mockNativeAttitude.setRotation.mockClear();

    const chip = renderer.root.findAll(
      (node) =>
        node.props.testID === `rotation-${mode}` &&
        typeof node.props.onPress === 'function',
    )[0];
    await ReactTestRenderer.act(() => {
      chip.props.onPress();
    });

    if (mode === 'auto') {
      // Already the default; the effect only re-runs on change.
      expect(mockNativeAttitude.setRotation).not.toHaveBeenCalled();
    } else {
      expect(mockNativeAttitude.setRotation).toHaveBeenCalledWith(mode);
    }
  },
);

test('the upside-down rotation chip is disabled on phones', async () => {
  // The test environment reports an iPhone (Platform.OS 'ios', Platform.isPad false).
  let renderer!: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  const chip = renderer.root.findAll(
    (node) =>
      node.props.testID === 'rotation-upsidedown' &&
      typeof node.props.onPress === 'function',
  )[0];
  expect(chip.props.disabled).toBe(true);
});
