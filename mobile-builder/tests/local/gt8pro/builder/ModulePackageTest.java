package local.gt8pro.builder;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.zip.*;
import local.gt8pro.moseybridge.GmsProfile;

public final class ModulePackageTest {
    public static void main(String[] args) throws Exception {
        String apkHash = "0123456789abcdef".repeat(4);
        GmsProfile profile = new GmsProfile(999999999L, apkHash, "abc", "N", "def", "h");
        if (!profile.equals(GmsProfile.parse(profile.serialize())) || profile.matches(999999998L, apkHash)
                || profile.matches(999999999L, "0".repeat(64))) throw new AssertionError("Profile identity");
        reject(() -> GmsProfile.parse(profile.serialize().replace(" def ", " ~/local ")));
        reject(() -> GmsProfile.parse(profile.serialize() + profile.serialize()));

        byte[] sample = "payload\n".getBytes(StandardCharsets.US_ASCII);
        byte[] payloadHashes = (ModulePackage.hash(sample) + "  sample\n").getBytes(StandardCharsets.US_ASCII);
        String oldManifest = ModulePackage.hash(payloadHashes) + "  payload.sha256\n";
        String pin = ModulePackage.hash(oldManifest.getBytes(StandardCharsets.US_ASCII));
        Map<String, byte[]> template = new TreeMap<>();
        template.put("payload/sample", sample);
        template.put("payload.sha256", payloadHashes);
        template.put("install.sha256", oldManifest.getBytes(StandardCharsets.US_ASCII));
        template.put("customize.sh", ("CHECK=" + pin + "\n").getBytes(StandardCharsets.US_ASCII));
        Path output = Files.createTempFile("gt8-builder-test", ".zip");
        try {
            ModulePackage.build(template(template), output.toFile(), profile);
            try (ZipFile zip = new ZipFile(output.toFile())) {
                String config = read(zip, GmsProfile.MODULE_PATH);
                if (!config.equals(profile.serialize())) throw new AssertionError("Generated profile mismatch");
                String manifest = read(zip, "install.sha256");
                if (!manifest.equals(oldManifest + ModulePackage.hash(config.getBytes(StandardCharsets.US_ASCII))
                        + "  " + GmsProfile.MODULE_PATH + "\n")) throw new AssertionError("Profile hash missing");
                if (!read(zip, "customize.sh").contains(
                        ModulePackage.hash(manifest.getBytes(StandardCharsets.US_ASCII))))
                    throw new AssertionError("Installer pin is stale");
            }
            template.put("payload/sample", new byte[]{0});
            reject(() -> ModulePackage.build(template(template), output.toFile(), profile));
        } finally {
            Files.deleteIfExists(output);
        }
        System.out.println("GENERATED_PROFILE_AND_INSTALL_CHAIN=PASS");
    }

    private static InputStream template(Map<String, byte[]> files) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            for (Map.Entry<String, byte[]> file : files.entrySet()) {
                zip.putNextEntry(new ZipEntry(file.getKey()));
                zip.write(file.getValue());
                zip.closeEntry();
            }
        }
        return new ByteArrayInputStream(bytes.toByteArray());
    }

    private static String read(ZipFile zip, String name) throws IOException {
        try (InputStream in = zip.getInputStream(zip.getEntry(name))) {
            return new String(in.readAllBytes(), StandardCharsets.US_ASCII);
        }
    }

    private interface Action {
        void run() throws Exception;
    }

    private static void reject(Action action) throws Exception {
        try {
            action.run();
        } catch (IOException | IllegalArgumentException expected) {
            return;
        }
        throw new AssertionError("Unexpectedly accepted malformed input");
    }
}
