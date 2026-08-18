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

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        redeliverSurface()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if (visibility == VISIBLE) {
            redeliverSurface()
        }
    }

    /**
     * Hand the current Surface to native again, if we already have a usable one.
     *
     * surfaceChanged is a ONE-SHOT. Android delivers it when the surface is created
     * or resized and never repeats it, and native blocks in getNativeWindow() until
     * that single delivery arrives - a 100 ms sleep loop with no timeout. Miss it
     * once and the RSX thread parks for the rest of the session: black game area,
     * ~3% CPU, and the boot log stopping dead. Rotating the device appears to fix it
     * only because a configuration change forces a fresh surfaceChanged.
     *
     * Reproduced on device 2026-08-18 by force-stopping the app and booting a title
     * immediately: the renderer sat in getNativeWindow() for 534 seconds before the
     * run was abandoned. That is almost certainly the README's "launching a second
     * game after closing the first can fail".
     *
     * Safe to repeat: _rpcsx_surfaceEvent compares the incoming ANativeWindow with
     * the one it holds and no-ops on a match. That was only made true just now - it
     * used to leak a reference on exactly this path, which is why re-delivery could
     * not be added before. From ARMSX3 614bf8b71.
     */
    private fun redeliverSurface() {
        // post(), not inline: onAttachedToWindow runs before layout, so width and
        // height are still 0 here, and a 0x0 surface is not worth delivering.
        post {
            val current = holder.surface

            if (current != null && current.isValid && width > 0 && height > 0) {
                Log.i("GraphicsFrame", "re-delivering surface ${width}x${height}")
                RPCSX.instance.surfaceEvent(current, 1)
            }
        }
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
