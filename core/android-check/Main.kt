// Compile-only check (core/check-android.sh): references a few LimeCore types so the generated
// Kotlin bindings must resolve against JNA. It is never run; running needs a device or emulator.
import uniffi.lime_core.LimeStore
import uniffi.lime_core.StoreException
import uniffi.lime_core.coreVersion
import uniffi.lime_core.encryptionSelfTest

fun checkBindings(): String {
    val report = encryptionSelfTest()
    val open: (String, ByteArray) -> LimeStore = { path, key -> LimeStore.open(path, key) }
    val failed: (StoreException) -> String = { it.message ?: "store error" }
    return "${coreVersion()} olm=${report.olmOk} megolm=${report.megolmOk} ${open.hashCode()} ${failed.hashCode()}"
}

fun main() {
    println(checkBindings())
}
