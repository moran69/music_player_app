package com.example.music_player_app

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import java.net.HttpURLConnection
import java.net.URL

/**
 * 系统悬浮窗胶囊（类灵动岛/华为流体云）
 * 用 ApplicationContext + TYPE_APPLICATION_OVERLAY 实现跨 App 悬浮显示。
 */
object FloatCapsuleManager {
    private var windowManager: WindowManager? = null
    private var capsuleView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var onPlayPauseTap: (() -> Unit)? = null
    private var onCapsuleTap: (() -> Unit)? = null

    private var initialX = 0f
    private var initialY = 0f
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false

    fun isShowing(): Boolean = capsuleView != null

    fun hasPermission(context: Context): Boolean = Settings.canDrawOverlays(context)

    fun openPermissionSettings(context: Context) {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    fun show(
        context: Context,
        title: String,
        artist: String,
        coverUrl: String?,
        isPlaying: Boolean,
        onPlayPause: () -> Unit,
        onTap: () -> Unit
    ) {
        if (capsuleView != null) {
            update(title, artist, coverUrl, isPlaying)
            return
        }
        if (!hasPermission(context)) return
        if (windowManager == null) {
            windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        }
        onPlayPauseTap = onPlayPause
        onCapsuleTap = onTap

        val view = LayoutInflater.from(context).inflate(R.layout.float_capsule, null)
        val titleView = view.findViewById<TextView>(R.id.fc_title)
        val artistView = view.findViewById<TextView>(R.id.fc_artist)
        val coverView = view.findViewById<ImageView>(R.id.fc_cover)
        val playBtn = view.findViewById<ImageButton>(R.id.fc_play)

        titleView.text = title
        artistView.text = artist
        playBtn.setImageResource(if (isPlaying) R.drawable.ic_pause_white else R.drawable.ic_play_white)
        if (!coverUrl.isNullOrEmpty()) {
            loadImage(coverUrl, coverView)
        }

        playBtn.setOnClickListener { onPlayPauseTap?.invoke() }

        view.setOnClickListener {
            onCapsuleTap?.invoke()
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                }
            if (launch != null) context.startActivity(launch)
        }

        view.setOnTouchListener { v, event ->
            val params = layoutParams
            if (params == null) return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x.toFloat()
                    initialY = params.y.toFloat()
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (!isDragging && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) isDragging = true
                    if (isDragging) {
                        params.x = (initialX + dx).toInt()
                        params.y = (initialY + dy).toInt()
                        windowManager?.updateViewLayout(v, params)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        v.performClick()
                    }
                    isDragging = false
                    true
                }
                else -> false
            }
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        params.y = 100
        params.x = 0

        layoutParams = params
        capsuleView = view
        try {
            windowManager?.addView(view, params)
        } catch (_: Exception) {
            capsuleView = null
        }
    }

    fun update(title: String, artist: String, coverUrl: String?, isPlaying: Boolean) {
        val view = capsuleView ?: return
        Handler(Looper.getMainLooper()).post {
            view.findViewById<TextView>(R.id.fc_title)?.text = title
            view.findViewById<TextView>(R.id.fc_artist)?.text = artist
            view.findViewById<ImageButton>(R.id.fc_play)?.setImageResource(
                if (isPlaying) R.drawable.ic_pause_white else R.drawable.ic_play_white
            )
            if (!coverUrl.isNullOrEmpty()) {
                loadImage(coverUrl, view.findViewById(R.id.fc_cover))
            }
        }
    }

    fun updatePlayState(isPlaying: Boolean) {
        val view = capsuleView ?: return
        Handler(Looper.getMainLooper()).post {
            view.findViewById<ImageButton>(R.id.fc_play)?.setImageResource(
                if (isPlaying) R.drawable.ic_pause_white else R.drawable.ic_play_white
            )
        }
    }

    fun hide() {
        val view = capsuleView ?: return
        try {
            windowManager?.removeView(view)
        } catch (_: Exception) {
        }
        capsuleView = null
        layoutParams = null
    }

    /** 简单网络图片加载（避免额外依赖，失败静默） */
    private fun loadImage(url: String, imageView: ImageView) {
        Thread {
            var conn: HttpURLConnection? = null
            try {
                conn = URL(url).openConnection() as HttpURLConnection
                conn.connectTimeout = 6000
                conn.readTimeout = 8000
                conn.connect()
                val stream = conn.inputStream
                val bitmap = BitmapFactory.decodeStream(stream)
                stream.close()
                if (bitmap != null) {
                    Handler(Looper.getMainLooper()).post { imageView.setImageBitmap(bitmap) }
                }
            } catch (_: Exception) {
            } finally {
                try {
                    conn?.disconnect()
                } catch (_: Exception) {
                }
            }
        }.start()
    }
}
