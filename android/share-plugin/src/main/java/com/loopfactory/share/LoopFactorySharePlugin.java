package com.loopfactory.share;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Native share sheet + App Link intake for Loop Factory (GDScript side: scripts/core/share.gd).
 *
 * share(): copies the file into cache/shared/ (the only folder the FileProvider exposes), builds an
 * ACTION_SEND intent with a content:// URI and FLAG_GRANT_READ_URI_PERMISSION (temporary, per-URI),
 * and opens the system chooser. Returns true when the chooser was started. Which app the player picks
 * is not reported (the game never claims a recipient got anything).
 *
 * consumeLaunchUri(): the https/loopfactory URI the activity was opened with, returned once.
 *
 * STATUS: not compiled or device-tested in the repository's build environment.
 */
public class LoopFactorySharePlugin extends GodotPlugin {
    private String lastHandledUri = "";

    public LoopFactorySharePlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "LoopFactoryShare";
    }

    @UsedByGodot
    public boolean share(String text, String absPath, String mime, String title) {
        final Activity activity = getActivity();
        if (activity == null) return false;
        try {
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType(mime == null || mime.isEmpty() ? "text/plain" : mime);
            if (text != null && !text.isEmpty()) send.putExtra(Intent.EXTRA_TEXT, text);
            if (absPath != null && !absPath.isEmpty()) {
                File src = new File(absPath);
                if (!src.isFile()) return false;
                File dir = new File(activity.getCacheDir(), "shared");
                if (!dir.isDirectory() && !dir.mkdirs()) return false;
                File dst = new File(dir, src.getName());
                copy(src, dst);
                Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".share", dst);
                send.putExtra(Intent.EXTRA_STREAM, uri);
                send.setClipData(ClipData.newRawUri("", uri)); // lets the grant reach the chooser's target
                send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            }
            Intent chooser = Intent.createChooser(send, title);
            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            activity.runOnUiThread(() -> activity.startActivity(chooser));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    @UsedByGodot
    public String consumeLaunchUri() {
        Activity activity = getActivity();
        if (activity == null || activity.getIntent() == null) return "";
        Uri data = activity.getIntent().getData();
        if (data == null) return "";
        String s = data.toString();
        if (s.equals(lastHandledUri)) return "";
        lastHandledUri = s;
        return s;
    }

    private static void copy(File src, File dst) throws IOException {
        try (InputStream in = new FileInputStream(src); OutputStream out = new FileOutputStream(dst)) {
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
    }
}
