package local.gt8pro.builder;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;

import local.gt8pro.gmsscan.ProfileProof;
import local.gt8pro.moseybridge.GmsProfile;

final class GmsSurvey {
    private static final String GMS = "com.google.android.gms";

    record Snapshot(long versionCode, String versionName, File apk, String hash) {}

    static Snapshot installed(PackageManager manager) throws Exception {
        PackageInfo info = manager.getPackageInfo(GMS, PackageManager.GET_SIGNING_CERTIFICATES);
        Signature[] signatures = info.signingInfo == null ? null : info.signingInfo.getApkContentsSigners();
        if (info.applicationInfo == null || !GMS.equals(info.packageName) || signatures == null
                || signatures.length != 1 || !GmsProfile.GOOGLE_SIGNER.equals(
                        ModulePackage.hash(signatures[0].toByteArray())))
            throw new IOException("Google Play 服务签名或身份不匹配。");
        File apk = new File(info.applicationInfo.sourceDir).getCanonicalFile();
        long size = apk.length(), modified = apk.lastModified();
        if (size < 1 || size > 256L * 1024 * 1024)
            throw new IOException("Google Play 服务 APK 大小超出范围。");
        String hash = ModulePackage.hash(new FileInputStream(apk), 256L * 1024 * 1024);
        if (size != apk.length() || modified != apk.lastModified())
            throw new IOException("Google Play 服务已变化，请重新检查。");
        return new Snapshot(info.getLongVersionCode(), info.versionName, apk, hash);
    }

    static GmsProfile scan(Snapshot snapshot) throws Exception {
        ProfileProof.Members members;
        try {
            members = ProfileProof.scan(snapshot.apk());
        } catch (Exception failure) {
            throw new IOException("未能确认唯一的 AirDrop 开关和横幅接口。");
        }
        GmsProfile profile = new GmsProfile(snapshot.versionCode(), snapshot.hash(),
                members.flagClass(), members.flagGetter(), members.homeFeaturesClass(), members.interopField());
        return GmsProfile.parse(profile.serialize());
    }

    static void requireCurrent(PackageManager manager, GmsProfile profile) throws Exception {
        Snapshot snapshot = installed(manager);
        if (!profile.matches(snapshot.versionCode(), snapshot.hash()))
            throw new IOException("Google Play 服务已更新，请重新检查后再生成模块。");
    }
}
