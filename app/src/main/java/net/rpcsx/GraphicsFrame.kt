package net.rpcsx

import android.content.Context
import android.os.Build
import android.util.AttributeSet
import android.util.Log
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView

class GraphicsFrame : SurfaceView, SurfaceHolder.Callback {
    private var preferredFrameRate = 0f

    constructor(context: Context) : super(context) {
        holder.addCallback(this)
    }

    constructor(context: Context?, attrs: AttributeSet?) : super(context, attrs) {
        holder.addCallback(this)
    }

    constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int) : super(
        context,
        attrs,
        defStyleAttr
    ) {
        holder.addCallback(this)
    }

    constructor(
        context: Context?,
        attrs: AttributeSet?,
        defStyleAttr: Int,
        defStyleRes: Int
    ) : super(context, attrs, defStyleAttr, defStyleRes) {
        holder.addCallback(this)
    }

    override fun surfaceCreated(p0: SurfaceHolder) {
        applyPreferredFrameRate(p0.surface)
        RPCSX.instance.surfaceEvent(p0.surface, 0)
    }

    override fun surfaceChanged(p0: SurfaceHolder, p1: Int, p2: Int, p3: Int) {
        RPCSX.instance.surfaceEvent(p0.surface, 1)
    }

    override fun surfaceDestroyed(p0: SurfaceHolder) {
        RPCSX.instance.surfaceEvent(p0.surface, 2)
    }

    fun setPreferredFrameRate(frameRate: Float) {
        preferredFrameRate = frameRate.coerceAtLeast(0f)
        if (holder.surface.isValid) {
            applyPreferredFrameRate(holder.surface)
        }
    }

    private fun applyPreferredFrameRate(surface: Surface) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || preferredFrameRate <= 0f) {
            return
        }

        runCatching {
            val compatibility = if (Build.VERSION.SDK_INT >= 36) {
                Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
            } else {
                Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                surface.setFrameRate(
                    preferredFrameRate,
                    compatibility,
                    Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS
                )
            } else {
                surface.setFrameRate(preferredFrameRate, compatibility)
            }
            Log.i(TAG, "Requested ${preferredFrameRate} FPS surface pacing")
        }.onFailure {
            Log.w(TAG, "Could not request $preferredFrameRate FPS surface pacing", it)
        }
    }

    private companion object {
        const val TAG = "RPCSX-DisplayPacing"
    }
}
