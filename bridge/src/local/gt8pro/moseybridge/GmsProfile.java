package local.gt8pro.moseybridge;

/** Reviewed mappings from stable Quick Share behavior to APK-specific DEX members. */
public record GmsProfile(long versionCode, String apkHash, String flagClass, String flagGetter,
        String homeFeaturesClass, String interopField) {
    public static final String GOOGLE_SIGNER =
            "5f2391277b1dbd489000467e4c2fa6af802430080457dce2f618992e9dfb5402";
    public static final String MODULE_PATH = "gt8pro-mosey-gms.profile";
    static final GmsProfile GMS_264330035 = new GmsProfile(264330035L,
            "8395c70a5e4ffbe2712aea7e1045d700b282f0a67d19b80686c595c991f12112",
            "keky", "O", "eouj", "h");
    static final GmsProfile GMS_264531035 = new GmsProfile(264531035L,
            "bd596149da4178510fdb00abf417747300e45e73b08433dadbd6e14b329ba6f2",
            "khsx", "L", "ersp", "h");

    private static final GmsProfile[] SUPPORTED = {GMS_264330035, GMS_264531035};

    static GmsProfile forVersion(long versionCode) throws Exception {
        for (GmsProfile profile : SUPPORTED)
            if (profile.versionCode() == versionCode) return profile;
        throw new Exception("GMS_UNSUPPORTED_VERSION");
    }

    static GmsProfile reviewed(long versionCode, String hash) {
        for (GmsProfile profile : SUPPORTED)
            if (profile.matches(versionCode, hash)) return profile;
        return null;
    }

    public boolean matches(long versionCode, String hash) {
        return this.versionCode == versionCode && apkHash.equals(hash);
    }

    public String serialize() {
        return "GT8GMS1 " + versionCode + " " + apkHash + " " + flagClass + " " + flagGetter
                + " " + homeFeaturesClass + " " + interopField + "\n";
    }

    public static GmsProfile parse(String value) {
        String part = "[A-Za-z_$][A-Za-z0-9_$]{0,127}";
        String name = part + "(?:\\." + part + ")*";
        if (value.length() > 512 || !value.matches("GT8GMS1 [1-9][0-9]{0,17} [0-9a-f]{64} "
                + name + " " + part + " " + name + " " + part + "\n"))
            throw new IllegalArgumentException("GMS_PROFILE_FORMAT");
        String[] fields = value.substring(0, value.length() - 1).split(" ");
        return new GmsProfile(Long.parseLong(fields[1]), fields[2], fields[3], fields[4], fields[5], fields[6]);
    }
}
