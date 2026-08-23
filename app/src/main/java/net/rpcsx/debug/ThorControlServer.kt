package net.rpcsx.debug

import android.util.Log
import net.rpcsx.BuildConfig
import net.rpcsx.Digital1Flags
import net.rpcsx.Digital2Flags
import net.rpcsx.RPCSX
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import kotlin.concurrent.thread

/**
 * A small control API inside the emulator, so a tool can drive it directly.
 *
 * ## Why this exists
 *
 * The emulated pad CANNOT be driven from outside the app. Three paths were
 * tried on this device and all three failed: `input keyevent BUTTON_START`
 * left the workload unchanged, `ENTER`/`BUTTON_A` reached the Android UI and
 * killed the process, and `sendevent` on the real gamepad node was confirmed
 * arriving in the kernel with `getevent` while the guest still saw nothing.
 *
 * So gameplay could not be reached over adb, and every large lever this fork
 * has found lives in gameplay: the SPU self-loop park is about 20% of gameplay
 * CPU, `process_mfc_cmd` is 20.13%, `vm::writer_lock` is 4.49%. None of them
 * could be measured on a title screen, which runs at 0.35 cores behind a frame
 * cap.
 *
 * This server calls `overlayPadData`, the same entry point the on-screen
 * overlay uses, so input arrives as real pad state inside the guest.
 *
 * ## Security
 *
 * It binds to the LOOPBACK address only, so nothing on the network can reach
 * it. The Thor is a shared device on a real network, and an open control port
 * on it would let anything drive the emulator. Reach it with a forward:
 *
 *     adb forward tcp:8099 tcp:8099
 *     curl 127.0.0.1:8099/status
 *
 * It runs in DEBUG BUILDS ONLY, gated on `BuildConfig.THOR_DEBUG_TOOLS`.
 *
 * ## Endpoints
 *
 *     GET  /                 this help
 *     GET  /status           emulator state, title id, version
 *     POST /pad              d1,d2,lx,ly,rx,ry   raw pad state, sticks 0..255
 *     POST /pad/press        buttons=CROSS,START&ms=120
 *     POST /pad/release      clear every button and centre the sticks
 *     POST /savestate        capture   (WARNING: one slot, it overwrites)
 *     POST /loadstate        restore
 *     POST /resume  /kill    emulation control
 *     GET  /setting?path=    read one config value
 *     POST /setting?path=&value=
 */
object ThorControlServer {
    private const val TAG = "ThorControl"
    private const val PORT = 8099
    private const val STICK_CENTRE = 128

    @Volatile
    private var started = false

    private val digital1 = Digital1Flags.entries.associateBy { it.name.removePrefix("CELL_PAD_CTRL_") }
    private val digital2 = Digital2Flags.entries.associateBy { it.name.removePrefix("CELL_PAD_CTRL_") }

    fun startIfDebug() {
        if (!BuildConfig.THOR_DEBUG_TOOLS || started) return
        started = true

        thread(isDaemon = true, name = "thor-control") {
            try {
                // Loopback only. See the security note above.
                ServerSocket(PORT, 8, InetAddress.getByName("127.0.0.1")).use { server ->
                    Log.i(TAG, "control API on 127.0.0.1:$PORT (adb forward tcp:$PORT tcp:$PORT)")
                    while (true) {
                        val client = try {
                            server.accept()
                        } catch (t: Throwable) {
                            Log.w(TAG, "accept failed: ${t.message}")
                            break
                        }
                        thread(isDaemon = true) { serve(client) }
                    }
                }
            } catch (t: Throwable) {
                // Report it. A control server that silently fails to bind looks
                // exactly like one that is running and ignoring you.
                Log.e(TAG, "control API did not start: ${t.message}")
            }
        }
    }

    private fun serve(socket: Socket) {
        socket.use { sock ->
            try {
                sock.soTimeout = 15000
                val reader = BufferedReader(InputStreamReader(sock.getInputStream()))
                val requestLine = reader.readLine() ?: return
                // Drain headers so the client is not left mid-write.
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.isEmpty()) break
                }

                val parts = requestLine.split(' ')
                if (parts.size < 2) {
                    respond(sock.getOutputStream(), 400, """{"error":"bad request line"}""")
                    return
                }

                val method = parts[0]
                val target = parts[1]
                val path = target.substringBefore('?')
                val query = parseQuery(target.substringAfter('?', ""))

                respond(sock.getOutputStream(), 200, route(method, path, query))
            } catch (t: Throwable) {
                Log.w(TAG, "request failed: ${t.message}")
            }
        }
    }

    private fun route(method: String, path: String, q: Map<String, String>): String {
        val rpcsx = RPCSX.instance

        return when (path) {
            "/" -> help()

            "/status" -> {
                val state = runCatching { rpcsx.getState() }.getOrDefault(-1)
                val title = runCatching { rpcsx.getTitleId() }.getOrDefault("")
                val version = runCatching { rpcsx.getVersion() }.getOrDefault("")
                """{"state":$state,"titleId":"${esc(title)}","version":"${esc(version)}","scene":${scene()}}"""
            }

            // Is a MOVIE playing? Pair this with your screenshot: a picture does
            // not say whether it is a cutscene or the game, and the frame rate
            // says it even less. Transformers renders its cutscene at 120 to 133
            // FPS and its title screen at 30, so a high number is a movie rather
            // than speed.
            "/scene" -> scene()

            // Heat, throttling, power, speed, and the REACH counters for the
            // levers this fork ships. Poll this instead of grepping the log.
            //
            // Read `thermalGuardEngaged` before believing a slow arm: an arm
            // pinned at exactly the guard's cap is a tripped guard, not a slow
            // configuration. And read the counters before believing a null: a
            // lever with no reach and a lever with no effect give the same
            // number.
            "/device" -> runCatching { RPCSX.instance.deviceInfo() }.getOrDefault("{}")

            "/pad" -> {
                val d1 = q["d1"]?.toIntOrNull() ?: 0
                val d2 = q["d2"]?.toIntOrNull() ?: 0
                val lx = q["lx"]?.toIntOrNull() ?: STICK_CENTRE
                val ly = q["ly"]?.toIntOrNull() ?: STICK_CENTRE
                val rx = q["rx"]?.toIntOrNull() ?: STICK_CENTRE
                val ry = q["ry"]?.toIntOrNull() ?: STICK_CENTRE
                val ok = rpcsx.overlayPadData(d1, d2, lx, ly, rx, ry)
                """{"ok":$ok,"d1":$d1,"d2":$d2,"lx":$lx,"ly":$ly,"rx":$rx,"ry":$ry}"""
            }

            "/pad/press" -> {
                val names = (q["buttons"] ?: "").split(',').map { it.trim().uppercase() }.filter { it.isNotEmpty() }
                if (names.isEmpty()) return """{"error":"buttons= is required","known":${knownButtons()}}"""

                var d1 = 0
                var d2 = 0
                val unknown = mutableListOf<String>()
                for (name in names) {
                    val a = digital1[name]
                    val b = digital2[name]
                    when {
                        a != null && a != Digital1Flags.None -> d1 = d1 or a.bit
                        b != null && b != Digital2Flags.None -> d2 = d2 or b.bit
                        else -> unknown += name
                    }
                }
                if (unknown.isNotEmpty()) {
                    return """{"error":"unknown buttons","unknown":${jsonList(unknown)},"known":${knownButtons()}}"""
                }

                val ms = (q["ms"]?.toLongOrNull() ?: 120L).coerceIn(1L, 5000L)
                rpcsx.overlayPadData(d1, d2, STICK_CENTRE, STICK_CENTRE, STICK_CENTRE, STICK_CENTRE)
                Thread.sleep(ms)
                rpcsx.overlayPadData(0, 0, STICK_CENTRE, STICK_CENTRE, STICK_CENTRE, STICK_CENTRE)
                """{"ok":true,"pressed":${jsonList(names)},"d1":$d1,"d2":$d2,"ms":$ms}"""
            }

            "/pad/release" -> {
                val ok = rpcsx.overlayPadData(0, 0, STICK_CENTRE, STICK_CENTRE, STICK_CENTRE, STICK_CENTRE)
                """{"ok":$ok}"""
            }

            // One slot, and it overwrites. A capture taken to test the load path
            // once destroyed the only savestate for a title.
            "/savestate" -> """{"ok":${runCatching { rpcsx.saveState() }.getOrDefault(false)},"warning":"one slot, overwrites"}"""
            "/loadstate" -> """{"ok":${runCatching { rpcsx.loadState() }.getOrDefault(false)}}"""

            "/resume" -> { runCatching { rpcsx.resume() }; """{"ok":true}""" }
            "/kill" -> { runCatching { rpcsx.kill() }; """{"ok":true}""" }

            "/setting" -> {
                val cfgPath = q["path"] ?: return """{"error":"path= is required"}"""
                if (method == "POST") {
                    val value = q["value"] ?: return """{"error":"value= is required"}"""
                    """{"ok":${runCatching { rpcsx.settingsSet(cfgPath, value) }.getOrDefault(false)}}"""
                } else {
                    """{"value":${runCatching { rpcsx.settingsGet(cfgPath) }.getOrDefault("null")}}"""
                }
            }

            else -> """{"error":"no such endpoint","path":"${esc(path)}"}"""
        }
    }

    /**
     * What the emulator KNOWS about the current scene.
     *
     * `videoDecoding` is exact: the guest hands access units to `cellVdec`, so a
     * recent decode IS pre-rendered video playing. There is no heuristic in it.
     *
     * A real-time engine cutscene is NOT covered, because the game renders it
     * rather than decoding it, so `cellVdec` never fires. `advice` says which of
     * the two cases you are in, and says `unknown` rather than guessing.
     */
    private fun scene(): String {
        val raw = runCatching { RPCSX.instance.sceneInfo() }.getOrDefault("{}")
        val playing = raw.contains("\"videoDecoding\":true")
        val advice = if (playing) "movie" else "not-a-movie-or-engine-cutscene"
        val inner = if (raw.length > 2) raw.trim().removePrefix("{").removeSuffix("}") else ""
        val sep = if (inner.isEmpty()) "" else ","
        return """{$inner$sep"advice":"$advice","note":"videoDecoding is exact for FMV; an engine cutscene is not detected here, judge it from the screenshot"}"""
    }

    private fun help() = """{"endpoints":[
"GET  /status",
"GET  /scene    is a movie playing? pair with your screenshot",
"GET  /device   heat, throttling, power, fps, cores, and lever reach counters",
"POST /pad?d1=&d2=&lx=&ly=&rx=&ry=   sticks 0..255, centre 128",
"POST /pad/press?buttons=CROSS,START&ms=120",
"POST /pad/release",
"POST /savestate   (one slot, overwrites)",
"POST /loadstate",
"POST /resume","POST /kill",
"GET  /setting?path=","POST /setting?path=&value="
],"buttons":${knownButtons()}}"""

    private fun knownButtons(): String {
        val names = (digital1.keys + digital2.keys).filter { it != "NONE" }.sorted()
        return jsonList(names)
    }

    private fun jsonList(items: List<String>) = items.joinToString(",", "[", "]") { "\"${esc(it)}\"" }

    private fun esc(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"")

    private fun parseQuery(raw: String): Map<String, String> {
        if (raw.isEmpty()) return emptyMap()
        val out = mutableMapOf<String, String>()
        for (pair in raw.split('&')) {
            if (pair.isEmpty()) continue
            val k = pair.substringBefore('=')
            val v = pair.substringAfter('=', "")
            out[dec(k)] = dec(v)
        }
        return out
    }

    private fun dec(s: String) = runCatching { URLDecoder.decode(s, "UTF-8") }.getOrDefault(s)

    private fun respond(out: OutputStream, code: Int, body: String) {
        val bytes = body.toByteArray(Charsets.UTF_8)
        val header = "HTTP/1.1 $code ${if (code == 200) "OK" else "Error"}\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: ${bytes.size}\r\n" +
            "Connection: close\r\n\r\n"
        out.write(header.toByteArray(Charsets.US_ASCII))
        out.write(bytes)
        out.flush()
    }
}
