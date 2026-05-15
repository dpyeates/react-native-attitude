package com.sensorworks.rnattitude

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

class RNAttitudePackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
    return if (name == RNAttitudeModule.NAME) {
      RNAttitudeModule(reactContext)
    } else {
      null
    }
  }

  override fun getReactModuleInfoProvider(): ReactModuleInfoProvider =
    ReactModuleInfoProvider {
      mapOf(
        RNAttitudeModule.NAME to
          ReactModuleInfo(
            RNAttitudeModule.NAME,
            RNAttitudeModule.NAME,
            false,
            false,
            false,
            false,
            true
          )
      )
    }
}
