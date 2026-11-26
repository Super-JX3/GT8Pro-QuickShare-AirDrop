package local.gt8pro.builder;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.DigestOutputStream;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.*;
import local.gt8pro.moseybridge.GmsProfile;

final class ModulePackage {
    static final long MAX_ZIP = 80L * 1024 * 1024;
    private static final long MAX_ENTRY = 20L * 1024 * 1024;
    private static final String INSTALL = "install.sha256";

    static void build(InputStream template, File output, GmsProfile profile) throws Exception {
        Map<String, byte[]> files = new TreeMap<>();
        long total = 0;
        try (ZipInputStream zip = new ZipInputStream(template)) {
            for (ZipEntry entry; (entry = zip.getNextEntry()) != null;) {
                String name = entry.getName();
                if (entry.isDirectory() || files.size() >= 3000 || !valid(name) || files.containsKey(name))
                    throw new IOException("模块模板不合法。");
                ByteArrayOutputStream content = new ByteArrayOutputStream();
                copy(zip, content, Math.min(MAX_ENTRY, MAX_ZIP - total));
                total += content.size();
                files.put(name, content.toByteArray());
            }
        }
        verify(files, INSTALL, "");
        verify(files, "payload.sha256", "payload/");
        addProfile(files, profile);
        verify(files, INSTALL, "");
        try (ZipOutputStream zip = new ZipOutputStream(new FileOutputStream(output))) {
            for (Map.Entry<String, byte[]> file : files.entrySet()) {
                ZipEntry entry = new ZipEntry(file.getKey());
                entry.setTime(0);
                zip.putNextEntry(entry);
                zip.write(file.getValue());
                zip.closeEntry();
            }
        }
        setUnixModes(output);
        try (ZipFile zip = new ZipFile(output)) {
            if (zip.size() != files.size()) throw new IOException("输出校验失败。");
            for (Map.Entry<String, byte[]> file : files.entrySet()) {
                ZipEntry entry = zip.getEntry(file.getKey());
                if (entry == null || !hash(zip.getInputStream(entry), MAX_ENTRY).equals(hash(file.getValue())))
                    throw new IOException("输出校验失败。");
            }
        }
    }

    private static void addProfile(Map<String, byte[]> files, GmsProfile profile) throws Exception {
        byte[] config = GmsProfile.parse(profile.serialize()).serialize().getBytes(StandardCharsets.US_ASCII);
        if (files.putIfAbsent(GmsProfile.MODULE_PATH, config) != null)
            throw new IOException("模板已包含 GMS 适配配置。");
        byte[] oldManifest = files.get(INSTALL);
        String manifest = new String(oldManifest, StandardCharsets.US_ASCII);
        if (!manifest.endsWith("\n")) throw new IOException("安装清单格式不匹配。");
        byte[] newManifest = (manifest + hash(config) + "  " + GmsProfile.MODULE_PATH + "\n")
                .getBytes(StandardCharsets.US_ASCII);
        String oldPin = hash(oldManifest);
        byte[] installer = files.get("customize.sh");
        if (installer == null) throw new IOException("缺少模块安装脚本。");
        String script = new String(installer, StandardCharsets.UTF_8);
        int offset = script.indexOf(oldPin);
        if (offset < 0 || offset != script.lastIndexOf(oldPin))
            throw new IOException("安装校验链不匹配。");
        files.put(INSTALL, newManifest);
        files.put("customize.sh", script.replace(oldPin, hash(newManifest)).getBytes(StandardCharsets.UTF_8));
    }

    private static boolean valid(String name) {
        return name.matches("[A-Za-z0-9_.+/-]+")
                && Arrays.stream(name.split("/", -1)).noneMatch(p -> p.isEmpty() || p.equals(".") || p.equals(".."));
    }

    private static void verify(Map<String, byte[]> files, String manifest, String prefix) throws Exception {
        byte[] contents = files.get(manifest);
        if (contents == null) throw new IOException("缺少校验清单。");
        Set<String> seen = new HashSet<>();
        for (String line : new String(contents, StandardCharsets.US_ASCII).split("\n")) {
            String[] parts = line.split("\\s+", 2);
            if (parts.length != 2 || !valid(parts[1]) || !seen.add(parts[1]))
                throw new IOException("校验清单格式不匹配。");
            byte[] content = files.get(prefix + parts[1]);
            if (content == null || !parts[0].equals(hash(content))) throw new IOException("模块文件校验失败。");
        }
    }

    static String hash(byte[] data) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
    }

    static String hash(InputStream source, long limit) throws Exception {
        try (InputStream in = source) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            copy(in, new DigestOutputStream(OutputStream.nullOutputStream(), digest), limit);
            return HexFormat.of().formatHex(digest.digest());
        }
    }

    static void copy(InputStream in, OutputStream out, long limit) throws IOException {
        byte[] buffer = new byte[65536];
        long total = 0;
        for (int read; (read = in.read(buffer)) != -1;) {
            if ((total += read) > limit) throw new IOException("文件过大。");
            out.write(buffer, 0, read);
        }
    }

    private static int read16(RandomAccessFile file) throws IOException {
        return file.readUnsignedByte() | (file.readUnsignedByte() << 8);
    }

    private static long read32(RandomAccessFile file) throws IOException {
        return read16(file) | ((long) read16(file) << 16);
    }

    private static void write16(RandomAccessFile file, int value) throws IOException {
        file.write(value & 255);
        file.write((value >>> 8) & 255);
    }

    private static void setUnixModes(File output) throws IOException {
        try (RandomAccessFile file = new RandomAccessFile(output, "rw")) {
            long end = file.length(), trailer = end - 22;
            file.seek(trailer);
            if (read32(file) != 0x06054b50L) throw new IOException("ZIP 目录无效。");
            file.seek(trailer + 10);
            int count = read16(file);
            file.seek(trailer + 16);
            long offset = read32(file);
            for (int i = 0; i < count; i++) {
                file.seek(offset);
                if (read32(file) != 0x02014b50L) throw new IOException("ZIP 目录无效。");
                file.seek(offset + 28);
                int nameLength = read16(file), extra = read16(file), comment = read16(file);
                file.seek(offset + 46);
                byte[] nameBytes = new byte[nameLength];
                file.readFully(nameBytes);
                String name = new String(nameBytes, StandardCharsets.US_ASCII);
                boolean executable = name.equals("service.sh") || name.endsWith("/update-binary");
                file.seek(offset + 4);
                write16(file, 0x0314);
                file.seek(offset + 38);
                write16(file, 0);
                write16(file, executable ? 0100755 : 0100644);
                offset += 46L + nameLength + extra + comment;
            }
        }
    }
}
