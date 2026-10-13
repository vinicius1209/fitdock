package dev.vinimachado.fitdock

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private lateinit var prefs: Prefs
    private lateinit var statusText: TextView
    private lateinit var permissionButton: Button
    private lateinit var batteryText: TextView
    private lateinit var batteryButton: Button
    private lateinit var codeInput: EditText
    private lateinit var hostInput: EditText
    private lateinit var resultText: TextView

    private val requestPermissions =
        registerForActivityResult(PermissionController.createRequestPermissionResultContract()) {
            refreshStatus()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        actionBar?.hide()
        prefs = Prefs(this)
        // Permite parear por adb: am start -n dev.vinimachado.fitdock/.MainActivity --es code XXXXXX
        intent.getStringExtra("code")?.let { prefs.code = it }
        setContentView(buildLayout())
        SyncWorker.schedule(this)
    }

    override fun onResume() {
        super.onResume()
        refreshStatus()
    }

    private fun refreshStatus() {
        resultText.text = prefs.lastResult
        val unrestricted = getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
        batteryText.text = if (unrestricted) {
            "Segundo plano: liberado, os envios seguem com o celular bloqueado."
        } else {
            "Segundo plano: restrito. Com o celular bloqueado o sistema corta a rede do app e os envios param."
        }
        batteryButton.visibility = if (unrestricted) View.GONE else View.VISIBLE
        lifecycleScope.launch {
            try {
                val missing = HealthReader.missingPermissions(this@MainActivity)
                if (missing.isEmpty()) {
                    statusText.text = "Health Connect: acesso liberado, inclusive em segundo plano."
                    permissionButton.visibility = View.GONE
                } else {
                    statusText.text = "Health Connect: faltam ${missing.size} permissões."
                    permissionButton.visibility = View.VISIBLE
                }
            } catch (e: HealthConnectUnavailable) {
                statusText.text = e.message
                permissionButton.visibility = View.GONE
            }
        }
    }

    private fun syncNow() {
        saveFields()
        resultText.text = "Sincronizando…"
        lifecycleScope.launch {
            SyncRunner.run(this@MainActivity)
            resultText.text = prefs.lastResult
        }
    }

    private fun saveFields() {
        prefs.code = codeInput.text.toString()
        prefs.manualHost = hostInput.text.toString()
    }

    private fun buildLayout(): View {
        val dp = resources.displayMetrics.density
        fun px(value: Int) = (value * dp).toInt()

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(24), px(24), px(24), px(24))
        }
        fun gap(height: Int) = View(this).also { column.addView(it, LinearLayout.LayoutParams(1, px(height))) }

        column.addView(TextView(this).apply {
            text = "FitDock"
            textSize = 30f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        })
        column.addView(TextView(this).apply {
            text = "Envia seus passos e batimentos do Health Connect para o FitDock do Mac, " +
                "a cada 15 minutos, pela rede de casa. Os dados não passam por nenhum servidor."
            alpha = 0.75f
        })
        gap(20)

        statusText = TextView(this).apply { textSize = 16f }
        column.addView(statusText)
        permissionButton = Button(this).apply {
            text = "Permitir acesso ao Health Connect"
            setOnClickListener { requestPermissions.launch(HealthReader.permissions) }
        }
        column.addView(permissionButton)
        gap(12)
        batteryText = TextView(this).apply { textSize = 16f }
        column.addView(batteryText)
        batteryButton = Button(this).apply {
            text = "Liberar uso em segundo plano"
            setOnClickListener {
                @Suppress("BatteryLife") // app pessoal: precisa rodar com o celular bloqueado
                val request = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                runCatching { startActivity(request) }
                    .onFailure { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
            }
        }
        column.addView(batteryButton)
        column.addView(Button(this).apply {
            text = "Abrir Health Connect"
            setOnClickListener {
                runCatching { startActivity(Intent("android.health.connect.action.HEALTH_HOME_SETTINGS")) }
                    .onFailure { Toast.makeText(this@MainActivity, "Não consegui abrir o Health Connect.", Toast.LENGTH_SHORT).show() }
            }
        })
        gap(20)

        column.addView(TextView(this).apply { text = "Código do Mac" })
        codeInput = EditText(this).apply {
            setText(prefs.code)
            hint = "6 letras, aparece no FitDock do Mac"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
            isSingleLine = true
        }
        column.addView(codeInput)
        gap(8)
        column.addView(TextView(this).apply { text = "Endereço do Mac (opcional)" })
        hostInput = EditText(this).apply {
            setText(prefs.manualHost)
            hint = "Vazio = encontrar sozinho. Ex.: 192.168.0.10:47800"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            isSingleLine = true
        }
        column.addView(hostInput)
        gap(12)

        column.addView(Button(this).apply {
            text = "Sincronizar agora"
            setOnClickListener { syncNow() }
        })
        gap(12)
        resultText = TextView(this).apply {
            gravity = Gravity.START
            alpha = 0.85f
        }
        column.addView(resultText)

        return ScrollView(this).apply {
            addView(column)
            setOnApplyWindowInsetsListener { view, insets ->
                @Suppress("DEPRECATION")
                view.setPadding(0, insets.systemWindowInsetTop, 0, insets.systemWindowInsetBottom)
                insets
            }
        }
    }
}
