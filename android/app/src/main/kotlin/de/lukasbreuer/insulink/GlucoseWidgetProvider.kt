package de.insulink

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.widget.RemoteViews

/**
 * The home-screen glucose widget: the latest value, its trend arrow, and how
 * long ago it arrived.
 *
 * It draws only what [GlucoseWidgetPlugin] last handed it — the value is
 * already formatted in the user's unit and the colour already reflects their
 * target range, so this class holds no glucose logic that could drift away from
 * the app's. Nothing here polls; `updatePeriodMillis` is 0 and every redraw is
 * either a push from the read pipeline or the launcher placing the widget.
 */
class GlucoseWidgetProvider : AppWidgetProvider() {
    companion object {
        private const val PREFS = "insulink_glucose_widget"
        private const val KEY_VALUE = "value"
        private const val KEY_UNIT = "unit"
        private const val KEY_ARROW = "arrow"
        private const val KEY_COLOR = "color"
        private const val KEY_TIME = "time"

        /** Shown until the first reading arrives (fresh install, sensor stopped). */
        private const val PLACEHOLDER = "--"

        /**
         * Persist the pushed reading and redraw every placed widget. Storing it
         * is what lets the launcher redraw on its own (rotation, reboot, a
         * widget added while the service is down) without asking Dart again.
         */
        fun publish(
            context: Context,
            value: String,
            unit: String,
            arrow: String,
            color: Int,
            timeMs: Long,
        ) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_VALUE, value)
                .putString(KEY_UNIT, unit)
                .putString(KEY_ARROW, arrow)
                .putInt(KEY_COLOR, color)
                .putLong(KEY_TIME, timeMs)
                .apply()
            redraw(context)
        }

        private fun redraw(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val provider = ComponentName(context, GlucoseWidgetProvider::class.java)
            for (id in manager.getAppWidgetIds(provider)) {
                manager.updateAppWidget(id, render(context))
            }
        }

        private fun render(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.glucose_widget)
            val value = prefs.getString(KEY_VALUE, null)
            views.setTextViewText(R.id.glucose_widget_value, value ?: PLACEHOLDER)
            views.setTextViewText(R.id.glucose_widget_arrow, prefs.getString(KEY_ARROW, ""))
            views.setTextViewText(R.id.glucose_widget_unit, prefs.getString(KEY_UNIT, ""))
            if (value != null) {
                views.setTextColor(R.id.glucose_widget_value, prefs.getInt(KEY_COLOR, 0))
            }
            showAge(views, prefs.getLong(KEY_TIME, 0L))
            views.setOnClickPendingIntent(R.id.glucose_widget_root, openApp(context))
            return views
        }

        /**
         * Count up from the reading's own timestamp, so a widget nobody is
         * pushing to visibly ages instead of presenting a stale number as if it
         * were current. A Chronometer ticks by itself, which is why no alarm or
         * periodic update is needed to keep this honest.
         *
         * The base is derived from the wall clock rather than persisted as
         * elapsed time, so it survives a reboot (elapsedRealtime restarts at
         * zero, System.currentTimeMillis does not), and it is clamped to "now"
         * so a clock jumped backwards cannot show a reading from the future.
         */
        private fun showAge(views: RemoteViews, timeMs: Long) {
            if (timeMs <= 0L) {
                views.setChronometer(R.id.glucose_widget_age, 0L, null, false)
                views.setTextViewText(R.id.glucose_widget_age, "")
                return
            }
            val now = SystemClock.elapsedRealtime()
            val base = (now - (System.currentTimeMillis() - timeMs)).coerceAtMost(now)
            views.setChronometer(R.id.glucose_widget_age, base, "%s", true)
        }

        private fun openApp(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, render(context))
        }
    }
}
