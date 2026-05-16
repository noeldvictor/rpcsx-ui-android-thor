package net.rpcsx;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;

public final class ThorDevCoreOverrideProvider extends ContentProvider {
    private static final String TAG = "ThorDevCore";
    private static final String PREFS_NAME = "app_prefs";
    private static final String CORE_PREF_KEY = "rpcsx_library";
    private static final String DEV_CORE_FLAG_KEY = "thor_dev_core_override";
    private static final String MARKER_RELATIVE_PATH = "dev-core/active-core.path";

    private static SharedPreferences.OnSharedPreferenceChangeListener listener;
    private static boolean applying;

    @Override
    public boolean onCreate() {
        Context context = getContext();
        if (context == null) {
            return true;
        }

        Context appContext = context.getApplicationContext();
        SharedPreferences prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        applyDevCoreOverride(appContext, prefs);

        listener = (sharedPreferences, key) -> {
            if (applying || !CORE_PREF_KEY.equals(key)) {
                return;
            }

            String devCorePath = readActiveCorePath(appContext);
            if (devCorePath == null) {
                return;
            }

            String currentPath = sharedPreferences.getString(CORE_PREF_KEY, "");
            if (!devCorePath.equals(currentPath)) {
                applyDevCoreOverride(appContext, sharedPreferences);
            }
        };
        prefs.registerOnSharedPreferenceChangeListener(listener);
        return true;
    }

    private static void applyDevCoreOverride(Context context, SharedPreferences prefs) {
        String devCorePath = readActiveCorePath(context);
        if (devCorePath == null) {
            if (prefs.getBoolean(DEV_CORE_FLAG_KEY, false)) {
                prefs.edit().remove(DEV_CORE_FLAG_KEY).apply();
            }
            return;
        }

        File devCore = new File(devCorePath);
        if (!devCore.isFile() || !devCore.canRead() || devCore.length() < 4096) {
            Log.w(TAG, "Ignoring invalid Thor dev core path: " + devCorePath);
            return;
        }

        String currentPath = prefs.getString(CORE_PREF_KEY, "");
        if (devCorePath.equals(currentPath) && prefs.getBoolean(DEV_CORE_FLAG_KEY, false)) {
            return;
        }

        applying = true;
        try {
            prefs.edit()
                .putString(CORE_PREF_KEY, devCorePath)
                .putBoolean(DEV_CORE_FLAG_KEY, true)
                .apply();
            Log.w(TAG, "Using Thor dev core override: " + devCorePath);
        } finally {
            applying = false;
        }
    }

    private static String readActiveCorePath(Context context) {
        String internalPath = readMarker(new File(context.getFilesDir(), MARKER_RELATIVE_PATH));
        if (internalPath != null) {
            return internalPath;
        }

        File externalFiles = context.getExternalFilesDir(null);
        if (externalFiles == null) {
            return null;
        }

        return readMarker(new File(externalFiles, MARKER_RELATIVE_PATH));
    }

    private static String readMarker(File marker) {
        if (!marker.isFile() || !marker.canRead()) {
            return null;
        }

        try (BufferedReader reader = new BufferedReader(new FileReader(marker))) {
            String line = reader.readLine();
            if (line == null) {
                return null;
            }

            line = line.trim();
            return line.isEmpty() ? null : line;
        } catch (IOException e) {
            Log.w(TAG, "Failed to read Thor dev core marker", e);
            return null;
        }
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        return null;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }
}
