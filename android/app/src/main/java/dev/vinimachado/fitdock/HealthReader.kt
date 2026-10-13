package dev.vinimachado.fitdock

import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

data class HeartSample(val at: Instant, val bpm: Int)

data class HeartStats(val min: Int, val max: Int, val avg: Int)

data class HealthSnapshot(
    val generatedAt: Instant,
    val steps: Long?,
    val activeCaloriesKcal: Double?,
    val totalCaloriesKcal: Double?,
    val distanceMeters: Double?,
    val heartRate: HeartSample?,
    val heartRateToday: HeartStats?,
    val heartRateSeries: List<HeartSample>,
)

class HealthConnectUnavailable(message: String) : Exception(message)

object HealthReader {
    val steps = HealthPermission.getReadPermission(StepsRecord::class)
    val heartRate = HealthPermission.getReadPermission(HeartRateRecord::class)

    val permissions = setOf(
        steps,
        heartRate,
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND,
    )

    private const val MAX_SERIES_POINTS = 300

    fun client(context: Context): HealthConnectClient {
        return when (HealthConnectClient.getSdkStatus(context)) {
            HealthConnectClient.SDK_AVAILABLE -> HealthConnectClient.getOrCreate(context)
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                throw HealthConnectUnavailable("O Health Connect precisa ser atualizado.")
            else -> throw HealthConnectUnavailable("O Health Connect não está disponível neste aparelho.")
        }
    }

    suspend fun missingPermissions(context: Context): Set<String> {
        val granted = client(context).permissionController.getGrantedPermissions()
        return permissions - granted
    }

    suspend fun read(context: Context): HealthSnapshot {
        val client = client(context)
        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        val startOfDay = ZonedDateTime.now(zone).toLocalDate().atStartOfDay(zone).toInstant()
        val today = TimeRangeFilter.between(startOfDay, now)

        // Cada métrica vai num pedido separado: se faltar uma permissão, as outras continuam.
        val steps = aggregate(client, StepsRecord.COUNT_TOTAL, today)
        val active = aggregate(client, ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL, today)?.inKilocalories
        val total = aggregate(client, TotalCaloriesBurnedRecord.ENERGY_TOTAL, today)?.inKilocalories
        val distance = aggregate(client, DistanceRecord.DISTANCE_TOTAL, today)?.inMeters

        val last24h = TimeRangeFilter.between(now.minus(24, ChronoUnit.HOURS), now)
        val samples = heartSamples(client, last24h)
        val todaySamples = samples.filter { it.at >= startOfDay }
        val stats = if (todaySamples.isEmpty()) null else HeartStats(
            min = todaySamples.minOf { it.bpm },
            max = todaySamples.maxOf { it.bpm },
            avg = todaySamples.map { it.bpm }.average().toInt(),
        )

        return HealthSnapshot(
            generatedAt = now,
            steps = steps,
            activeCaloriesKcal = active,
            totalCaloriesKcal = total,
            distanceMeters = distance,
            heartRate = samples.lastOrNull(),
            heartRateToday = stats,
            heartRateSeries = downsample(todaySamples),
        )
    }

    private suspend fun <T : Any> aggregate(
        client: HealthConnectClient,
        metric: AggregateMetric<T>,
        range: TimeRangeFilter,
    ): T? {
        return try {
            client.aggregate(AggregateRequest(metrics = setOf(metric), timeRangeFilter = range))[metric]
        } catch (e: SecurityException) {
            null
        }
    }

    private suspend fun heartSamples(client: HealthConnectClient, range: TimeRangeFilter): List<HeartSample> {
        val result = mutableListOf<HeartSample>()
        var pageToken: String? = null
        try {
            do {
                val response = client.readRecords(
                    ReadRecordsRequest(
                        recordType = HeartRateRecord::class,
                        timeRangeFilter = range,
                        pageSize = 5000,
                        pageToken = pageToken,
                    )
                )
                response.records.forEach { record ->
                    record.samples.forEach { result += HeartSample(it.time, it.beatsPerMinute.toInt()) }
                }
                pageToken = response.pageToken
            } while (pageToken != null)
        } catch (e: SecurityException) {
            return emptyList()
        }
        return result.sortedBy { it.at }
    }

    private fun downsample(samples: List<HeartSample>): List<HeartSample> {
        if (samples.size <= MAX_SERIES_POINTS) return samples
        val step = samples.size.toDouble() / MAX_SERIES_POINTS
        return (0 until MAX_SERIES_POINTS).map { samples[(it * step).toInt()] } + samples.last()
    }

    /** Nome que a pessoa deu ao aparelho (ex.: "Galaxy S24"); cai no modelo se não houver. */
    fun deviceName(context: Context): String =
        Settings.Global.getString(context.contentResolver, "device_name")?.takeIf { it.isNotBlank() }
            ?: Build.MODEL
            ?: "Android"
}
