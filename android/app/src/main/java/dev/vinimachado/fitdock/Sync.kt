package dev.vinimachado.fitdock

import android.content.Context
import androidx.core.content.edit
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.IOException
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit

class Prefs(context: Context) {
    private val prefs = context.getSharedPreferences("fitdock", Context.MODE_PRIVATE)

    var code: String
        get() = prefs.getString("code", "") ?: ""
        set(value) = prefs.edit { putString("code", value.trim().uppercase()) }

    /** Endereço digitado à mão ("ip:porta"). Vazio = descobrir sozinho. */
    var manualHost: String
        get() = prefs.getString("manual_host", "") ?: ""
        set(value) = prefs.edit { putString("manual_host", value.trim()) }

    var discoveredHost: String
        get() = prefs.getString("discovered_host", "") ?: ""
        set(value) = prefs.edit { putString("discovered_host", value) }

    var lastResult: String
        get() = prefs.getString("last_result", "") ?: ""
        set(value) = prefs.edit { putString("last_result", value) }
}

object SyncRunner {
    /** Lê o Health Connect e envia ao Mac. Devolve a mensagem para mostrar na tela. */
    suspend fun run(context: Context): Result<String> {
        val prefs = Prefs(context)
        val outcome = runCatching {
            if (prefs.code.isBlank()) error("Informe o código mostrado no FitDock do Mac.")
            // Sem passos nem batimentos não há o que mostrar; enviar apagaria o último dado bom do Mac.
            val missing = HealthReader.missingPermissions(context)
            if (HealthReader.steps in missing && HealthReader.heartRate in missing) {
                error("Dê acesso ao Health Connect no app FitDock.")
            }
            val snapshot = HealthReader.read(context)
            val host = sendSomewhere(context, prefs, snapshot)
            buildString {
                append("Enviado às ${LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))} para $host. ")
                append("Passos: ${snapshot.steps ?: "sem dado"}. ")
                append("Último batimento: ${snapshot.heartRate?.bpm?.let { "$it bpm" } ?: "sem dado"}.")
            }
        }
        prefs.lastResult = outcome.getOrElse { "Falhou: ${it.message ?: it.javaClass.simpleName}" }
        return outcome
    }

    private suspend fun sendSomewhere(context: Context, prefs: Prefs, snapshot: HealthSnapshot): String {
        val manual = prefs.manualHost
        if (manual.isNotBlank()) {
            MacClient.send(context, manual, prefs.code, snapshot)
            return manual
        }
        val cached = prefs.discoveredHost
        if (cached.isNotBlank()) {
            try {
                MacClient.send(context, cached, prefs.code, snapshot)
                return cached
            } catch (e: IOException) {
                // O IP do Mac pode ter mudado: procura de novo.
            }
        }
        val found = MacClient.discover(context)
            ?: throw IOException("Não encontrei o FitDock do Mac na rede. O Mac está ligado e na mesma Wi-Fi?")
        MacClient.send(context, found, prefs.code, snapshot)
        prefs.discoveredHost = found
        return found
    }
}

class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val outcome = SyncRunner.run(applicationContext)
        val error = outcome.exceptionOrNull()
        return if (error is IOException) Result.retry() else Result.success()
    }

    companion object {
        private const val NAME = "fitdock-sync"

        /**
         * 15 minutos é o menor intervalo que o Android permite para trabalho periódico.
         * Sem exigir "rede conectada": o Android só considera atendido com internet validada,
         * e o envio é pela rede local. Se o Mac não responder, o worker tenta de novo.
         */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
