package dev.vinimachado.fitdock

import android.content.Context
import android.util.Log
import androidx.core.content.edit
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
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
            val (host, nextSync) = sendSomewhere(context, prefs, snapshot)
            FollowUpWorker.schedule(context, nextSync ?: DEFAULT_NEXT_SYNC_SECONDS)
            buildString {
                append("Enviado às ${LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))} para $host. ")
                append("Passos: ${snapshot.steps ?: "sem dado"}. ")
                append("Último batimento: ${snapshot.heartRate?.bpm?.let { "$it bpm" } ?: "sem dado"}.")
            }
        }
        prefs.lastResult = outcome.getOrElse { "Falhou: ${it.message ?: it.javaClass.simpleName}" }
        outcome.exceptionOrNull()?.let { Log.w(TAG, "Sincronização falhou", it) } ?: Log.i(TAG, prefs.lastResult)
        // Fora de casa (ou Mac desligado) não adianta insistir: tenta de novo com calma.
        if (outcome.isFailure && prefs.code.isNotBlank()) {
            FollowUpWorker.schedule(context, OFFLINE_NEXT_SYNC_SECONDS)
        }
        return outcome
    }

    private const val TAG = "FitDock"
    private const val DEFAULT_NEXT_SYNC_SECONDS = 180
    private const val OFFLINE_NEXT_SYNC_SECONDS = 600

    /** Devolve o endereço usado e o intervalo pedido pelo Mac. */
    private suspend fun sendSomewhere(context: Context, prefs: Prefs, snapshot: HealthSnapshot): Pair<String, Int?> {
        val manual = prefs.manualHost
        if (manual.isNotBlank()) {
            return manual to MacClient.send(context, manual, prefs.code, snapshot)
        }
        val cached = prefs.discoveredHost
        if (cached.isNotBlank()) {
            try {
                return cached to MacClient.send(context, cached, prefs.code, snapshot)
            } catch (e: IOException) {
                // O IP do Mac pode ter mudado: procura de novo.
                Log.w(TAG, "Falha no endereço conhecido $cached: $e")
            }
        }
        val found = MacClient.discover(context)
            ?: throw IOException("Não encontrei o FitDock do Mac na rede. O Mac está ligado e na mesma Wi-Fi?")
        val nextSync = MacClient.send(context, found, prefs.code, snapshot)
        prefs.discoveredHost = found
        return found to nextSync
    }
}

/**
 * Envio seguinte, no intervalo que o Mac pediu (45 s com o painel aberto, 3 min fora disso).
 * O periódico de 15 min continua como rede de segurança caso esta corrente se perca.
 */
class FollowUpWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        // SyncRunner já agenda o próximo; não há retry aqui para a corrente não se duplicar.
        SyncRunner.run(applicationContext)
        return Result.success()
    }

    companion object {
        private const val NAME = "fitdock-next"

        fun schedule(context: Context, delaySeconds: Int) {
            val request = OneTimeWorkRequestBuilder<FollowUpWorker>()
                .setInitialDelay(delaySeconds.toLong(), TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(NAME, ExistingWorkPolicy.REPLACE, request)
        }
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
         *
         * Sem condição de rede, de propósito: na Samsung o app em segundo plano fica congelado
         * com a rede negada (OEM_DENY), e o agendador nunca daria a condição como atendida.
         * A tarefa sem condição roda, a Samsung descongela o app para ela, e com a otimização
         * de bateria liberada (ver MainActivity) o Android não corta a rede (APP_BACKGROUND).
         */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
