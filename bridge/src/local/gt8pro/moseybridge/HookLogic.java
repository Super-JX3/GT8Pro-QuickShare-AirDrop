package local.gt8pro.moseybridge;

/** Android-free decisions used by the actual hook callbacks. */
public final class HookLogic {
    public static final String INSTANCE = "com.google.android.moseyservice.IMoseyService/default";
    public static final String DESCRIPTOR = "com.google.android.moseyservice.IMoseyService";
    private HookLogic() {}
    public static boolean target(String pkg, String process, int uid, int sdk, String firmware) {
        return uid >= 10000 && uid < 100000 && sdk == 36
                && "RMX5200_16.0.10.501(CN01)".equals(firmware)
                && ("com.google.android.gms".equals(pkg) || "com.google.android.mosey".equals(pkg))
                && pkg.equals(process);
    }
    public static boolean enable(boolean adapter, boolean active, long now, long deadline,
            boolean threw, Object value, int arguments) {
        return adapter && active && now < deadline && !threw && arguments == 0
                && Boolean.FALSE.equals(value);
    }
    public interface BinderView {
        boolean alive() throws Exception;
        String descriptor() throws Exception;
        Object value();
    }
    public interface Lookup { BinderView check() throws Exception; }
    public static final class Decision {
        public final boolean intercept;
        public final Object binder;
        public final String event;
        Decision(boolean i, Object b, String e) { intercept=i; binder=b; event=e; }
    }
    public static Decision lookupDeclared(String name, boolean adapter, boolean active,
            long now, long deadline, Object declared, Lookup lookup) {
        if(!Boolean.FALSE.equals(declared))return new Decision(false,null,"DECLARATION_NOT_FALSE");
        return lookup(name,adapter,active,now,deadline,lookup);
    }
    public static Decision lookup(String name, boolean adapter, boolean active,
            long now, long deadline, Lookup lookup) {
        if (!INSTANCE.equals(name) || !adapter || !active || now >= deadline)
            return new Decision(false, null, "PASSTHROUGH");
        try {
            BinderView b = lookup.check();
            if (b == null) return new Decision(false, null, "REAL_BINDER_ABSENT");
            if (!b.alive()) return new Decision(false, null, "REAL_BINDER_DEAD");
            if (!DESCRIPTOR.equals(b.descriptor()))
                return new Decision(false, null, "DESCRIPTOR_MISMATCH");
            Object value=b.value();
            return new Decision(value!=null, value, value==null?"REAL_BINDER_ABSENT":"REAL_BINDER_VERIFIED");
        } catch (Exception failure) {
            return new Decision(false, null, "LOOKUP_ERROR");
        }
    }
}
