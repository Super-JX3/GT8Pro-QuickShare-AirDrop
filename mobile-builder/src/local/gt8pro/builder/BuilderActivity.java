package local.gt8pro.builder;

import android.app.Activity;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;

import local.gt8pro.moseybridge.GmsProfile;

public final class BuilderActivity extends Activity {
    private static final int SAVE_MODULE = 12, SAVE_BRIDGE = 13;
    private TextView status;
    private Button assemble, bridge, scan;
    private GmsProfile profile, pendingProfile;
    private File pendingModule;
    private boolean busy;

    @Override public void onCreate(Bundle state) {
        boolean dark = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
        setTheme(dark ? android.R.style.Theme_Material_NoActionBar
                : android.R.style.Theme_Material_Light_NoActionBar);
        super.onCreate(state);
        restorePending(state);

        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(pad, pad, pad, pad);
        TextView title = new TextView(this);
        title.setText("Quick Share 模块构建助手");
        title.setTextSize(24);
        content.addView(title);
        status = new TextView(this);
        status.setTextSize(15);
        status.setPadding(0, pad, 0, pad);
        content.addView(status);

        assemble = new Button(this);
        assemble.setText("生成适配模块");
        assemble.setOnClickListener(view -> generate());
        content.addView(assemble);
        bridge = new Button(this);
        bridge.setText("导出配套桥接 APK");
        bridge.setOnClickListener(view -> save(SAVE_BRIDGE, "application/vnd.android.package-archive",
                "GT8Pro-MoseyBridge-0.12.7.apk"));
        content.addView(bridge);
        scan = new Button(this);
        scan.setText("重新检查 Google Play 服务");
        scan.setOnClickListener(view -> inspect());
        content.addView(scan);

        TextView note = new TextView(this);
        note.setText("扫描和生成均在手机本地完成。生成后需用 KernelSU 安装模块，并安装配套桥接 APK、在 LSPosed 启用。");
        note.setPadding(0, pad, 0, 0);
        content.addView(note);
        ScrollView scroll = new ScrollView(this);
        scroll.setOnApplyWindowInsetsListener((view, insets) -> {
            Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return insets;
        });
        scroll.addView(content);
        setContentView(scroll);
        WindowInsetsController controller = getWindow().getInsetsController();
        if (controller != null) {
            int mask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            controller.setSystemBarsAppearance(dark ? 0 : mask, mask);
        }
        scroll.requestApplyInsets();
        inspect();
    }

    private void restorePending(Bundle state) {
        if (state == null) return;
        String name = state.getString("pending");
        String serialized = state.getString("profile");
        if (name == null || !name.matches("module-[0-9]+\\.zip") || serialized == null) return;
        File file = new File(getCacheDir(), name);
        if (!file.isFile()) return;
        try {
            pendingProfile = GmsProfile.parse(serialized);
            pendingModule = file;
        } catch (IllegalArgumentException ignored) {
            file.delete();
        }
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        if (pendingModule != null) {
            state.putString("pending", pendingModule.getName());
            state.putString("profile", pendingProfile.serialize());
        }
    }

    private void updateButtons() {
        assemble.setEnabled(!busy && profile != null && pendingModule == null);
        bridge.setEnabled(!busy && profile != null && pendingModule == null);
        scan.setEnabled(!busy && pendingModule == null);
    }

    private void checkDevice() throws IOException {
        if (!Profiles.matches(Build.MODEL, Build.DISPLAY, Build.VERSION.SDK_INT,
                Arrays.asList(Build.SUPPORTED_ABIS)))
            throw new IOException("当前仅支持 RMX5200 和已验证的 Android 16 固件。");
    }

    private void inspect() {
        if (busy) return;
        profile = null;
        busy = true;
        updateButtons();
        status.setText("正在检查固件和签名，并扫描 AirDrop 适配点…");
        new Thread(() -> {
            try {
                checkDevice();
                GmsSurvey.Snapshot installed = GmsSurvey.installed(getPackageManager());
                GmsProfile result = GmsSurvey.scan(installed);
                GmsSurvey.requireCurrent(getPackageManager(), result);
                runOnUiThread(() -> {
                    profile = result;
                    finish("已匹配 Google Play 服务 " + installed.versionName()
                            + " 的 AirDrop 开关和横幅，可生成适配模块。"
                            + "\n安装后请实测发现和传输。");
                });
            } catch (Exception failure) {
                runOnUiThread(() -> finish(message("无法生成适配模块。", failure)));
            }
        }, "gt8-gms-scan").start();
    }

    private void generate() {
        if (busy || profile == null || pendingModule != null) return;
        GmsProfile selected = profile;
        busy = true;
        updateButtons();
        status.setText("正在生成模块并校验安装清单…");
        new Thread(() -> {
            File temp = null;
            try {
                checkDevice();
                GmsSurvey.requireCurrent(getPackageManager(), selected);
                temp = File.createTempFile("module-", ".zip", getCacheDir());
                ModulePackage.build(getAssets().open("template.zip"), temp, selected);
                File ready = temp;
                temp = null;
                runOnUiThread(() -> {
                    if (isDestroyed()) {
                        ready.delete();
                        return;
                    }
                    pendingModule = ready;
                    pendingProfile = selected;
                    finish("模块校验通过，请选择保存位置。");
                    save(SAVE_MODULE, "application/zip", "GT8Pro-QuickShare-0.16.6-"
                            + selected.versionCode() + ".zip");
                });
            } catch (Exception failure) {
                runOnUiThread(() -> finish(message("生成模块失败。", failure)));
            } finally {
                if (temp != null) temp.delete();
            }
        }, "gt8-module-build").start();
    }

    private void save(int request, String mimeType, String name) {
        Intent picker = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType(mimeType).putExtra(Intent.EXTRA_TITLE, name);
        startActivityForResult(picker, request);
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != SAVE_MODULE && request != SAVE_BRIDGE) return;
        File module = request == SAVE_MODULE ? pendingModule : null;
        GmsProfile selected = pendingProfile;
        if (request == SAVE_MODULE) {
            pendingModule = null;
            pendingProfile = null;
        }
        if (result != RESULT_OK || data == null || data.getData() == null
                || (request == SAVE_MODULE && module == null)) {
            if (module != null) module.delete();
            updateButtons();
            return;
        }
        Uri uri = data.getData();
        busy = true;
        updateButtons();
        new Thread(() -> export(uri, module, selected), "gt8-export").start();
    }

    private void export(Uri uri, File module, GmsProfile selected) {
        boolean opened = false;
        try {
            if (module != null) GmsSurvey.requireCurrent(getPackageManager(), selected);
            try (InputStream in = module == null ? getAssets().open("bridge.apk") : new FileInputStream(module);
                 OutputStream out = getContentResolver().openOutputStream(uri, "wt")) {
                if (out == null) throw new IOException("无法打开保存位置。");
                opened = true;
                ModulePackage.copy(in, out, module == null ? 1024L * 1024 : ModulePackage.MAX_ZIP);
            }
            runOnUiThread(() -> finish(module == null ? "桥接 APK 已导出。"
                    : "适配模块已生成。请与配套桥接 APK 一起安装。"));
        } catch (Exception failure) {
            String prefix = opened ? "保存失败，目标文件可能不完整。" : "未写入文件。";
            runOnUiThread(() -> finish(message(prefix, failure)));
        } finally {
            if (module != null) module.delete();
        }
    }

    private void finish(String message) {
        if (isDestroyed()) return;
        busy = false;
        status.setText(message);
        updateButtons();
    }

    private static String message(String prefix, Exception failure) {
        return failure instanceof IOException && failure.getMessage() != null
                ? prefix + "\n" + failure.getMessage() : prefix;
    }
}
