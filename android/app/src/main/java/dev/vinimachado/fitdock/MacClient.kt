package dev.vinimachado.fitdock

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.URL
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.coroutines.resume

class InvalidCodeException : Exception("O Mac recusou o código. Confira o código mostrado no FitDock do Mac.")

object MacClient {
    private const val SERVICE_TYPE = "_fitdock._tcp."
    private const val DISCOVERY_TIMEOUT_MS = 8_000L

    /** Envia o snapshot. Lança IOException se o Mac não responder. */
    suspend fun send(context: Context, host: String, code: String, snapshot: HealthSnapshot) = withContext(Dispatchers.IO) {
        val body = toJson(context, snapshot).toString().toByteArray(Charsets.UTF_8)
        val connection = URL("http://$host/v1/snapshot").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 4_000
            connection.readTimeout = 6_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $code")
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            when (val status = connection.responseCode) {
                200 -> Unit
                401 -> throw InvalidCodeException()
                else -> throw IOException("O Mac respondeu com erro $status.")
            }
        } finally {
            connection.disconnect()
        }
    }

    /** Procura o FitDock do Mac na rede local por Bonjour. Devolve "ip:porta" ou null. */
    suspend fun discover(context: Context): String? = withTimeoutOrNull(DISCOVERY_TIMEOUT_MS) {
        val nsd = context.getSystemService(NsdManager::class.java)
        suspendCancellableCoroutine { cont ->
            var resolving = false
            val discovery = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String) = Unit
                override fun onDiscoveryStopped(serviceType: String) = Unit
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                    if (cont.isActive) cont.resume(null)
                }
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
                override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

                override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                    if (resolving) return
                    resolving = true
                    val listener = this
                    @Suppress("DEPRECATION")
                    nsd.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                            resolving = false
                        }

                        override fun onServiceResolved(info: NsdServiceInfo) {
                            val address = ipv4Of(info)
                            if (address != null && cont.isActive) {
                                runCatching { nsd.stopServiceDiscovery(listener) }
                                cont.resume("$address:${info.port}")
                            } else {
                                resolving = false
                            }
                        }
                    })
                }
            }
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery)
            cont.invokeOnCancellation { runCatching { nsd.stopServiceDiscovery(discovery) } }
        }
    }

    private fun ipv4Of(info: NsdServiceInfo): String? {
        val addresses = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            info.hostAddresses
        } else {
            @Suppress("DEPRECATION")
            listOfNotNull(info.host)
        }
        return addresses.firstOrNull { it is Inet4Address }?.hostAddress
    }

    private fun toJson(context: Context, s: HealthSnapshot): JSONObject {
        val zone = ZoneId.systemDefault()
        fun date(instant: Instant): String =
            OffsetDateTime.ofInstant(instant.truncatedTo(ChronoUnit.SECONDS), zone)
                .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
        fun sample(h: HeartSample) = JSONObject().put("at", date(h.at)).put("bpm", h.bpm)

        return JSONObject().apply {
            put("version", 1)
            put("device", HealthReader.deviceName(context))
            put("generatedAt", date(s.generatedAt))
            s.steps?.let { put("steps", it) }
            s.activeCaloriesKcal?.let { put("activeCaloriesKcal", it) }
            s.totalCaloriesKcal?.let { put("totalCaloriesKcal", it) }
            s.distanceMeters?.let { put("distanceMeters", it) }
            s.heartRate?.let { put("heartRate", sample(it)) }
            s.heartRateToday?.let {
                put("heartRateToday", JSONObject().put("min", it.min).put("max", it.max).put("avg", it.avg))
            }
            put("heartRateSeries", JSONArray(s.heartRateSeries.map(::sample)))
        }
    }
}
