package com.shauchmap.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class WidgetProviderMedium : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout_medium).apply {
                val intentUri = Uri.parse("shauchmap://emergency")
                val pendingIntentWithData = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    intentUri
                )
                setOnClickPendingIntent(R.id.widget_btn_emergency, pendingIntentWithData)
                setOnClickPendingIntent(R.id.widget_root, pendingIntentWithData)

                val lastUpdated = widgetData.getString("last_updated", "Waiting for update...")
                setTextViewText(R.id.widget_last_updated, lastUpdated)

                // Read top 3 toilets
                val t1Name = widgetData.getString("med_1_name", "Locating...")
                val t1Dist = widgetData.getString("med_1_dist", "")
                val t1Id = widgetData.getString("med_1_id", "")

                val t2Name = widgetData.getString("med_2_name", "")
                val t2Dist = widgetData.getString("med_2_dist", "")
                val t2Id = widgetData.getString("med_2_id", "")

                val t3Name = widgetData.getString("med_3_name", "")
                val t3Dist = widgetData.getString("med_3_dist", "")
                val t3Id = widgetData.getString("med_3_id", "")

                setTextViewText(R.id.widget_name_1, t1Name)
                setTextViewText(R.id.widget_dist_1, t1Dist)
                if (t1Id != null && t1Id.isNotEmpty()) {
                    setOnClickPendingIntent(R.id.widget_row_1, HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("shauchmap://navigate?toiletId=$t1Id")
                    ))
                }

                setTextViewText(R.id.widget_name_2, t2Name)
                setTextViewText(R.id.widget_dist_2, t2Dist)
                if (t2Id != null && t2Id.isNotEmpty()) {
                    setOnClickPendingIntent(R.id.widget_row_2, HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("shauchmap://navigate?toiletId=$t2Id")
                    ))
                }

                setTextViewText(R.id.widget_name_3, t3Name)
                setTextViewText(R.id.widget_dist_3, t3Dist)
                if (t3Id != null && t3Id.isNotEmpty()) {
                    setOnClickPendingIntent(R.id.widget_row_3, HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("shauchmap://navigate?toiletId=$t3Id")
                    ))
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
