package com.cairnlabworks.okanzo

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity is required by local_auth so the biometric prompt can
 * attach to a FragmentActivity. FLAG_SECURE is enabled by default to keep
 * balances out of screenshots and the recents thumbnail, and can be toggled
 * from Settings -> Security via [SECURITY_CHANNEL].
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val blockScreenshots = runCatching {
            getSharedPreferences(FLUTTER_PREFERENCES, MODE_PRIVATE)
                .getBoolean(KEY_BLOCK_SCREENSHOTS, true)
        }.getOrDefault(true)
        applyScreenshotProtection(blockScreenshots)
    }

    private fun applyScreenshotProtection(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens https links (such as the privacy policy) in the user's browser; see lib/util/link_opener.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LINKS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "openUrl") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val uri = (call.arguments as? String)?.let(Uri::parse)
            if (uri == null || uri.scheme != "https") {
                result.success(false)
                return@setMethodCallHandler
            }
            try {
                startActivity(Intent(Intent.ACTION_VIEW, uri))
                result.success(true)
            } catch (e: ActivityNotFoundException) {
                result.success(false)
            }
        }
        // Updates or queries FLAG_SECURE when the user toggles Block screenshots; see lib/util/screenshot_protection.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setScreenshotProtection" -> {
                    val enabled = call.arguments as? Boolean
                    if (enabled == null) {
                        result.error("INVALID_ARGUMENT", "Expected a boolean argument", null)
                        return@setMethodCallHandler
                    }
                    applyScreenshotProtection(enabled)
                    result.success(isScreenshotProtectionEnabled() == enabled)
                }
                "isScreenshotProtectionEnabled" -> {
                    result.success(isScreenshotProtectionEnabled())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isScreenshotProtectionEnabled(): Boolean =
        (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0

    private companion object {
        const val LINKS_CHANNEL = "com.cairnlabworks.okanzo/links"
        const val SECURITY_CHANNEL = "com.cairnlabworks.okanzo/security"
        const val FLUTTER_PREFERENCES = "FlutterSharedPreferences"
        const val KEY_BLOCK_SCREENSHOTS = "flutter.block_screenshots"
    }
}
