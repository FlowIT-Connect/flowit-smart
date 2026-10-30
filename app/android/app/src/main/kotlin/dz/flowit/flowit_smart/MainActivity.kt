package dz.flowit.flowit_smart

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.ttlock.ttlock_flutter.TtlockFlutterPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Ouvre une autre application (Smart Life pour coupler un appareil Tuya).
        // Renvoie le paquet ouvert, « store » si seule la fiche Play Store a pu s'ouvrir, ou null.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "solea/apps").setMethodCallHandler { call, result ->
            if (call.method != "open") return@setMethodCallHandler result.notImplemented()
            val packages = call.argument<List<String>>("packages") ?: emptyList()
            for (pkg in packages) {
                val launch = packageManager.getLaunchIntentForPackage(pkg) ?: continue
                startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return@setMethodCallHandler result.success(pkg)
            }
            val first = packages.firstOrNull() ?: return@setMethodCallHandler result.success(null)
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$first")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success("store")
            } catch (e: ActivityNotFoundException) {
                result.success(null)
            }
        }
    }

    // Le module TTLock demande l'autorisation Bluetooth : il doit recevoir la réponse.
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val ttlock = flutterEngine?.plugins?.get(TtlockFlutterPlugin::class.java) as TtlockFlutterPlugin?
        ttlock?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
