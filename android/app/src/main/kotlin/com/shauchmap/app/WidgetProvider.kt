package com.shauchmap.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class WidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                val nearestLooName = widgetData.getString("nearest_loo_name", "Locating...")
                val nearestLooDist = widgetData.getString("nearest_loo_dist", "")
                val lastUpdated = widgetData.getString("last_updated", "Waiting for update...")
                val toiletId = widgetData.getString("toilet_id", "")

                setTextViewText(R.id.widget_toilet_name, nearestLooName)
                setTextViewText(R.id.widget_distance, nearestLooDist)
                setTextViewText(R.id.widget_last_updated, lastUpdated)

                val emergencyIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("shauchmap://emergency")
                )
                setOnClickPendingIntent(R.id.widget_root, emergencyIntent)

                if (toiletId != null && toiletId.isNotEmpty()) {
                    val navigateIntent = HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("shauchmap://navigate?toiletId=$toiletId")
                    )
                    setOnClickPendingIntent(R.id.widget_content, navigateIntent)
                } else {
                    setOnClickPendingIntent(R.id.widget_content, emergencyIntent)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
