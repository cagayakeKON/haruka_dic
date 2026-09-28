package app.haruka.dictionary

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "app.haruka.dictionary/notifications"
        const val NOTIFICATION_CHANNEL = "learning_messages"
        const val NOTIFICATION_ID = 1742
        const val REQUEST_NOTIFICATIONS = 1743
        const val EXTRA_OPEN_NOTIFICATIONS = "open_notifications"
        const val PREFS = "notification_permission"
        const val ASKED = "asked"
    }

    private var channel: MethodChannel? = null
    private var pendingOpen = false
    private var pendingCount = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingOpen = intent?.getBooleanExtra(EXTRA_OPEN_NOTIFICATIONS, false) == true
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "showUnreadCount" -> {
                        val count = call.arguments as? Int
                        if (count == null || count < 0) {
                            result.error("invalid_count", "Invalid unread count", null)
                        } else {
                            showUnreadCount(count)
                            result.success(null)
                        }
                    }
                    "clear" -> {
                        clearNotification()
                        result.success(null)
                    }
                    "consumeOpenRequest" -> {
                        val open = pendingOpen
                        pendingOpen = false
                        result.success(open)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(EXTRA_OPEN_NOTIFICATIONS, false)) {
            pendingOpen = true
            channel?.invokeMethod("openNotifications", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS &&
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        ) {
            postSummary(pendingCount)
        }
    }

    private fun manager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager().createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "学习消息",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "已授权的学习任务消息摘要"
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                },
            )
        }
    }

    private fun showUnreadCount(count: Int) {
        pendingCount = count
        if (count == 0) {
            clearNotification()
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(ASKED, false)) {
                prefs.edit().putBoolean(ASKED, true).apply()
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
            }
            return
        }
        postSummary(count)
    }

    private fun postSummary(count: Int) {
        if (count <= 0 ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !manager().areNotificationsEnabled())
        ) return
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_NOTIFICATIONS, true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_haruka)
            .setContentTitle("Haruka 学习消息")
            .setContentText("有 $count 条未读消息，点按查看")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        manager().notify(NOTIFICATION_ID, notification)
    }

    private fun clearNotification() {
        pendingCount = 0
        manager().cancel(NOTIFICATION_ID)
    }
}
