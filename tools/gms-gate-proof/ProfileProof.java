package local.gt8pro.gmsscan;

import java.io.File;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import moseyPLK.client.GmsDexFile;
import moseyPLK.client.GmsDexFile.ClassDef;
import moseyPLK.client.GmsDexFile.Instruction;
import moseyPLK.client.GmsDexFile.Method;

/** Finds a candidate mapping in a signed APK without loading any of its classes. */
public final class ProfileProof {
    public record Members(String flagClass, String flagGetter, String homeFeaturesClass, String interopField) {}
    private static final String SERVICE =
            "Lcom/google/android/gms/nearby/sharing/NearbySharingChimeraService;";
    private static final String INTEROP_LABEL = "isInteropSharingEnabled=";
    private static final String BOX = "Ljava/lang/Boolean;->valueOf(Z)Ljava/lang/Boolean;";

    public static void main(String[] args) throws Exception {
        Members m = scan(new File(args[0]));
        System.out.println(m.flagClass() + " " + m.flagGetter() + " "
                + m.homeFeaturesClass() + " " + m.interopField());
    }

    public static Members scan(File apk) throws Exception {
        if (apk.length() < 1 || apk.length() > 256L * 1024 * 1024)
            throw new IllegalArgumentException("Unsupported GMS APK size");
        long deadline = System.nanoTime() + 60_000_000_000L;
        try (GmsDexFile dex = GmsDexFile.readApk(apk)) {
            Method getter = findSharingFlag(dex, deadline);
            Home home = findHomeFeatures(dex, deadline);
            return new Members(className(getter.owner), getter.name, className(home.owner()), home.field());
        }
    }

    private static Method findSharingFlag(GmsDexFile dex, long deadline) throws Exception {
        ClassDef service = dex.findClass(SERVICE);
        Method serviceInit = dex.findMethod(SERVICE + "-><init>()V");
        if (serviceInit == null) throw new IllegalStateException("Quick Share service constructor missing");
        List<Method> matches = new ArrayList<>();
        List<Instruction> code = serviceInit.code().instructions;
        int receiver = constructorReceiver(code, service.superclass, serviceInit.code().registersSize - 1);
        for (int i = 0; i + 4 < code.size(); i++) {
            Instruction allocation = code.get(i), constructor = code.get(i + 1);
            Instruction memoize = code.get(i + 2), result = code.get(i + 3), store = code.get(i + 4);
            if (!allocation.opname.equals("new-instance") || !constructor.opname.equals("invoke-direct")
                    || !(allocation.reference + "-><init>()V").equals(constructor.reference)
                    || !memoize.opname.equals("invoke-static") || !result.opname.equals("move-result-object")
                    || !store.opname.equals("iput-object") || !store.reference.startsWith(SERVICE + "->")
                    || !Arrays.equals(constructor.registers, allocation.registers)
                    || !Arrays.equals(memoize.registers, allocation.registers)
                    || result.registers[0] != store.registers[0]
                    || store.registers[1] != receiver) continue;
            String supplierType = store.reference.substring(store.reference.lastIndexOf(':') + 1);
            if (!memoize.reference.endsWith("(" + supplierType + ")" + supplierType)) continue;
            ClassDef supplier = dex.findClass(allocation.reference);
            if (supplier == null || !supplier.interfaces.contains(supplierType)) continue;
            for (Method method : supplier.methods) {
                if (!method.parameterTypes.isEmpty() || !method.returnType.equals("Ljava/lang/Object;")
                        || Modifier.isStatic(method.accessFlags)) continue;
                if (method.code() == null) continue;
                Method resolved = matchProviderGate(dex, method.code().instructions, deadline);
                if (resolved != null) matches.add(resolved);
            }
        }
        return unique(matches, "Quick Share provider flag");
    }

    private static int constructorReceiver(List<Instruction> code, String superclass, int receiver) {
        boolean serviceAction = false;
        int alias = receiver;
        for (Instruction ins : code) {
            if (ins.opname.startsWith("const-string")
                    && "com.google.android.gms.nearby.sharing.START_SERVICE".equals(ins.reference))
                serviceAction = true;
            if (ins.opname.startsWith("move-object") && ins.registers.length == 2
                    && ins.registers[1] == receiver) alias = ins.registers[0];
            if (serviceAction && ins.opname.startsWith("invoke-direct")
                    && (superclass + "-><init>(ILjava/lang/String;Ljava/util/Set;II)V").equals(ins.reference)
                    && ins.registers[0] == alias) return alias;
        }
        throw new IllegalStateException("Quick Share base constructor changed");
    }

    private static Method matchProviderGate(GmsDexFile dex, List<Instruction> code, long deadline) throws Exception {
        String[] shape = {"sget", "sget-object", "invoke-virtual", "move-result-object",
                "invoke-interface", "move-result", "const/4", "if-nez", "invoke-virtual",
                "move-result-object", "invoke-interface", "move-result", "if-nez", "const/4",
                "invoke-static", "move-result-object", "return-object"};
        if (code.size() != shape.length) return null;
        for (int i = 0; i < shape.length; i++)
            if (!code.get(i).opname.equals(shape[i])) return null;
        if (!code.get(0).reference.startsWith(SERVICE + "->")
                || !code.get(2).reference.equals(code.get(8).reference)
                || !code.get(4).reference.endsWith("()Z") || !code.get(10).reference.endsWith("()Z")
                || code.get(6).literal != 1 || code.get(13).literal != 0
                || !BOX.equals(code.get(14).reference)
                || code.get(7).target != code.get(14).pc || code.get(12).target != code.get(14).pc)
            return null;
        int configuration = code.get(1).registers[0], enabled = code.get(6).registers[0];
        if (!uses(code, 2, configuration) || !uses(code, 4, code.get(3).registers[0])
                || !uses(code, 7, code.get(5).registers[0]) || !uses(code, 8, configuration)
                || !uses(code, 10, code.get(9).registers[0]) || !uses(code, 12, code.get(11).registers[0])
                || !uses(code, 13, enabled) || !uses(code, 14, enabled)
                || !uses(code, 16, code.get(15).registers[0])) return null;
        Method first = dex.findMethod(code.get(4).reference), second = dex.findMethod(code.get(10).reference);
        if (first == null || second == null || !first.owner.equals(second.owner) || first == second
                || !code.get(2).reference.endsWith("()" + first.owner)) return null;
        List<Method> implementations = new ArrayList<>();
        for (String descriptor : dex.classDescriptors()) {
            checkTime(deadline);
            ClassDef type = dex.readClass(descriptor);
            if (!type.interfaces.contains(first.owner) || Modifier.isAbstract(type.accessFlags)) continue;
            Method a = dex.findMethod(type.descriptor + "->" + first.name + "()Z");
            Method b = dex.findMethod(type.descriptor + "->" + second.name + "()Z");
            if (readsKey(dex, a, "45704091") && readsKey(dex, b, "45830365")) implementations.add(a);
        }
        return implementations.isEmpty() ? null : unique(implementations, "provider flag implementation");
    }

    private static boolean uses(List<Instruction> code, int i, int register) {
        return Arrays.equals(code.get(i).registers, new int[]{register});
    }

    private static boolean readsKey(GmsDexFile dex, Method getter, String key) throws Exception {
        if (getter == null || Modifier.isStatic(getter.accessFlags) || getter.code() == null) return false;
        List<Instruction> code = getter.code().instructions;
        if (!code.get(code.size() - 1).opname.equals("return")) return false;
        if (hasFlagKey(code, key)) return true;
        Instruction first = code.get(0);
        if (!first.opname.equals("invoke-static") || first.registers.length != 0
                || !first.reference.startsWith(getter.owner + "->")) return false;
        Method helper = dex.findMethod(first.reference);
        return helper != null && Modifier.isStatic(helper.accessFlags) && helper.code() != null
                && hasFlagKey(helper.code().instructions, key);
    }

    private static boolean hasFlagKey(List<Instruction> code, String key) {
        for (int i = 0; i + 1 < code.size(); i++) {
            Instruction literal = code.get(i), call = code.get(i + 1);
            if (literal.opname.startsWith("const-string") && key.equals(literal.reference)
                    && call.opname.equals("invoke-virtual") && call.registers.length == 4
                    && call.reference.contains("(ILjava/lang/String;Z)")
                    && call.registers[2] == literal.registers[0]) return true;
        }
        return false;
    }

    private record Home(String owner, String field) {}

    private static Home findHomeFeatures(GmsDexFile dex, long deadline) throws Exception {
        List<Home> matches = new ArrayList<>();
        for (String descriptor : dex.classDescriptors()) {
            checkTime(deadline);
            ClassDef type = dex.readClass(descriptor);
            Method constructor = method(type, type.descriptor + "-><init>(Z)V");
            if (constructor == null || constructor.code() == null) continue;
            Method toString = method(type, type.descriptor + "->toString()Ljava/lang/String;");
            if (toString == null || toString.code() == null) continue;
            List<Instruction> code = toString.code().instructions;
            for (int i = 0; i + 3 < code.size(); i++) {
                Instruction label = code.get(i), start = code.get(i + 1);
                Instruction read = code.get(i + 2), append = code.get(i + 3);
                if (!label.opname.startsWith("const-string") || !label.reference.startsWith("HomeFeatures(")
                        || !label.reference.endsWith(INTEROP_LABEL)
                        || !"Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V".equals(start.reference)
                        || !read.opname.equals("iget-boolean") || !read.reference.startsWith(type.descriptor + "->")
                        || !read.reference.endsWith(":Z") || read.registers[1] != toString.code().registersSize - 1
                        || !"Ljava/lang/StringBuilder;->append(Z)Ljava/lang/StringBuilder;".equals(append.reference)
                        || !Arrays.equals(append.registers, new int[]{start.registers[0], read.registers[0]}))
                    continue;
                int argument = constructor.code().registersSize - 1;
                for (Instruction ins : constructor.code().instructions) {
                    if (read.reference.equals(ins.reference) && ins.opname.equals("iput-boolean")
                            && Arrays.equals(ins.registers, new int[]{argument, argument - 1}))
                        matches.add(new Home(type.descriptor, read.reference.substring(
                                type.descriptor.length() + 2, read.reference.length() - 2)));
                }
            }
        }
        return unique(matches, "HomeFeatures capability");
    }

    private static Method method(ClassDef type, String descriptor) {
        for (Method method : type.methods)
            if (method.descriptor.equals(descriptor)) return method;
        return null;
    }

    private static void checkTime(long deadline) {
        if (System.nanoTime() >= deadline) throw new IllegalStateException("GMS scan timed out");
    }

    private static <T> T unique(List<T> matches, String description) {
        if (matches.size() != 1)
            throw new IllegalStateException(description + " expected one match, found " + matches.size());
        return matches.get(0);
    }

    private static String className(String descriptor) {
        return descriptor.substring(1, descriptor.length() - 1).replace('/', '.');
    }
}
