package com.a11.weatherstone.weatherstone

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class WeatherStoneWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    val animateWidget = widgetData.getBoolean(KEY_ANIMATE_WIDGET, false)
    val imagePath = widgetData.getString("stone_image", null)

    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.weatherstone_widget).apply {
        val launchIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        setOnClickPendingIntent(R.id.widget_root, launchIntent)

        setTextViewText(
          R.id.widget_location,
          widgetData.getString("location_label", "현재 위치") ?: "현재 위치",
        )
        setTextViewText(
          R.id.widget_temperature,
          widgetData.getString("temperature_label", "--") ?: "--",
        )
        setTextViewText(
          R.id.widget_condition,
          widgetData.getString("condition_label", "날씨 반영 대기") ?: "날씨 반영 대기",
        )
        setTextViewText(
          R.id.widget_accessory,
          widgetData.getString("accessory_label", "맨돌") ?: "맨돌",
        )

        if (animateWidget) {
          setViewVisibility(R.id.widget_anim, View.VISIBLE)
          setViewVisibility(R.id.widget_image, View.GONE)
          setViewVisibility(R.id.widget_placeholder, View.GONE)
        } else if (imagePath != null) {
          val bitmap = BitmapFactory.decodeFile(imagePath)
          if (bitmap != null) {
            setImageViewBitmap(R.id.widget_image, bitmap)
            setViewVisibility(R.id.widget_image, View.VISIBLE)
            setViewVisibility(R.id.widget_anim, View.GONE)
            setViewVisibility(R.id.widget_placeholder, View.GONE)
          } else {
            setViewVisibility(R.id.widget_image, View.GONE)
            setViewVisibility(R.id.widget_anim, View.GONE)
            setViewVisibility(R.id.widget_placeholder, View.VISIBLE)
          }
        } else {
          setViewVisibility(R.id.widget_image, View.GONE)
          setViewVisibility(R.id.widget_anim, View.GONE)
          setViewVisibility(R.id.widget_placeholder, View.VISIBLE)
        }
      }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  companion object {
    private const val KEY_ANIMATE_WIDGET = "animate_widget"
  }
}
