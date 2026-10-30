package dz.flowit.flowit_smart

import com.ttlock.ttlock_flutter.TtlockFlutterPlugin
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Le module TTLock demande l'autorisation Bluetooth : il doit recevoir la réponse.
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val ttlock = flutterEngine?.plugins?.get(TtlockFlutterPlugin::class.java) as TtlockFlutterPlugin?
        ttlock?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
