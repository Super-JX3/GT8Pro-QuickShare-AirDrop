// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Weverses/OPAirDrop native/OPAirShareLSPosed.java, commit 28a3a1d.
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Root installer. Targeted transactions; LSPosed reloads the configuration on reboot. */
public final class GT8ProLSPosedSetup {
    private static final String PKG = "local.gt8pro.moseybridge";
    private static final String DB = "/data/adb/lspd/config/modules_config.db";

    private static String quote(String value) {
        if (value.indexOf('\n') >= 0 || value.indexOf('\r') >= 0 || value.indexOf('\0') >= 0)
            throw new IllegalArgumentException("invalid APK path");
        return "'" + value.replace("'", "''") + "'";
    }

    // Shared with the host regression tests; SQL never deletes existing scopes/configs.
    static List<String> statements(String layout, String apk) {
        if (!apk.startsWith("/data/app/") || !apk.endsWith("/base.apk"))
            throw new IllegalArgumentException("unexpected APK path");
        String pkg = quote(PKG);
        List<String> sql = new ArrayList<>();
        sql.add("INSERT OR IGNORE INTO modules (module_pkg_name,apk_path) VALUES (" + pkg + "," + quote(apk) + ")");
        sql.add("UPDATE modules SET apk_path=" + quote(apk) + " WHERE module_pkg_name=" + pkg);
        if (layout.equals("modern")) {
            sql.add("INSERT OR IGNORE INTO modules_state (module_pkg_name,user_id,enabled) VALUES (" + pkg + ",0,1)");
            sql.add("UPDATE modules_state SET enabled=1 WHERE module_pkg_name=" + pkg + " AND user_id=0");
        } else if (layout.equals("legacy")) {
            sql.add("UPDATE modules SET enabled=1 WHERE module_pkg_name=" + pkg);
        } else throw new IllegalArgumentException("unknown LSPosed schema");
        for (String target : new String[]{"com.google.android.gms", "com.google.android.mosey"}) {
            if (layout.equals("modern")) {
                sql.add("INSERT OR IGNORE INTO scope (module_pkg_name,app_pkg_name,user_id) VALUES (" + pkg + "," + quote(target) + ",0)");
            } else {
                sql.add("INSERT OR IGNORE INTO scope (mid,app_pkg_name,user_id) SELECT mid," + quote(target) + ",0 FROM modules WHERE module_pkg_name=" + pkg);
            }
        }
        return sql;
    }

    private static Set<String> columns(SQLiteDatabase db, String table) {
        Set<String> result = new HashSet<>();
        try (Cursor c = db.rawQuery("PRAGMA table_info(" + table + ")", null)) {
            while (c.moveToNext()) result.add(c.getString(c.getColumnIndexOrThrow("name")));
        }
        return result;
    }

    private static void require(Set<String> columns, String... names) {
        for (String name : names)
            if (!columns.contains(name)) throw new IllegalStateException("unsupported LSPosed schema: " + name);
    }

    private static long scalar(SQLiteDatabase db, String sql) {
        try (Cursor c = db.rawQuery(sql, null)) {
            if (!c.moveToFirst()) throw new IllegalStateException("missing query result");
            return c.getLong(0);
        }
    }

    private static String otherRowsDigest(SQLiteDatabase db, String layout) throws Exception {
        java.security.MessageDigest sha=java.security.MessageDigest.getInstance("SHA-256");
        String[] tables=layout.equals("modern")?new String[]{"modules","modules_state","scope"}:new String[]{"modules","scope"};
        for(String table:tables){
            String exclude=table.equals("scope")&&layout.equals("legacy")
                ? "mid NOT IN (SELECT mid FROM modules WHERE module_pkg_name='"+PKG+"')"
                : "module_pkg_name<>'"+PKG+"'";
            java.util.ArrayList<String> rows=new java.util.ArrayList<>();
            try(Cursor c=db.rawQuery("SELECT * FROM "+table+" WHERE "+exclude,null)){
                while(c.moveToNext()){
                    if(rows.size()>10000)throw new IllegalStateException("row_budget");
                    StringBuilder row=new StringBuilder();
                    for(int i=0;i<c.getColumnCount();i++){
                        int type=c.getType(i);row.append(type).append(":");
                        if(type==Cursor.FIELD_TYPE_BLOB){byte[] b=c.getBlob(i);row.append(java.util.Arrays.toString(b));}
                        else if(type!=Cursor.FIELD_TYPE_NULL){String v=c.getString(i);row.append(v.length()).append(":").append(v);}
                        row.append(";");
                    }
                    rows.add(row.toString());
                }
            }
            java.util.Collections.sort(rows);
            sha.update(table.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            for(String row:rows){sha.update(row.getBytes(java.nio.charset.StandardCharsets.UTF_8));sha.update((byte)0);}
        }
        return java.util.Arrays.toString(sha.digest());
    }

    public static void main(String[] args) throws Exception {
        // Allows testing the exact activation SQL with real SQLite on the host.
        if (args.length == 3 && args[0].equals("--sql")) {
            for (String sql : statements(args[1], args[2])) System.out.println(sql + ";");
            return;
        }
        boolean inspect = args.length == 3 && args[0].equals("--check");
        if (inspect) args = new String[]{args[1], args[2]};
        if (android.os.Process.myUid() != 0 || args.length != 2 || !args[0].equals(DB))
            throw new IllegalArgumentException("root installer and LSPosed config path required");
        Path path = Path.of(args[0]);
        if (!Files.isRegularFile(path) || Files.isSymbolicLink(path) || !Files.isRegularFile(Path.of(args[1])))
            throw new IllegalArgumentException("missing database or installed APK");
        // Oplus SQLiteGlobal.getDefaultSyncMode() assumes a framework-initialized
        // resource array that standalone app_process does not have. Explicit
        // FULL synchronization bypasses that default without relaxing durability.
        SQLiteDatabase.OpenParams params = new SQLiteDatabase.OpenParams.Builder()
            .setOpenFlags(inspect ? SQLiteDatabase.OPEN_READONLY : SQLiteDatabase.OPEN_READWRITE)
            .setSynchronousMode("FULL").build();
        try (SQLiteDatabase db = SQLiteDatabase.openDatabase(path.toFile(), params)) {
            Set<String> modules = columns(db, "modules");
            require(modules, "module_pkg_name", "apk_path");
            String layout = modules.contains("mid") && modules.contains("enabled") ? "legacy" : "modern";
            require(columns(db, "scope"), layout.equals("modern") ? "module_pkg_name" : "mid", "app_pkg_name", "user_id");
            if (layout.equals("modern")) require(columns(db, "modules_state"), "module_pkg_name", "user_id", "enabled");
            String bridgeOwner = layout.equals("modern") ? "module_pkg_name='" + PKG + "'"
                : "mid=(SELECT mid FROM modules WHERE module_pkg_name='" + PKG + "')";
            if (scalar(db, "SELECT COUNT(*) FROM modules WHERE module_pkg_name='" + PKG + "'") > 1)
                throw new IllegalStateException("ambiguous_module_owner");
            long extraScopes = scalar(db, "SELECT COUNT(*) FROM scope WHERE " + bridgeOwner
                + " AND (user_id<>0 OR app_pkg_name NOT IN ('com.google.android.gms','com.google.android.mosey'))");
            if (extraScopes != 0) throw new IllegalStateException("unexpected_existing_scopes");
            if (inspect) {
                String enabledQuery = layout.equals("modern")
                    ? "SELECT COUNT(*) FROM modules_state WHERE module_pkg_name='" + PKG + "' AND user_id=0 AND enabled=1"
                    : "SELECT COUNT(*) FROM modules WHERE module_pkg_name='" + PKG + "' AND enabled=1";
                String owner = layout.equals("modern") ? "module_pkg_name='" + PKG + "'"
                    : "mid=(SELECT mid FROM modules WHERE module_pkg_name='" + PKG + "')";
                long scopes = scalar(db, "SELECT COUNT(*) FROM scope WHERE " + owner
                    + " AND user_id=0 AND app_pkg_name IN ('com.google.android.gms','com.google.android.mosey')");
                long apkMatches = scalar(db, "SELECT COUNT(*) FROM modules WHERE module_pkg_name='" + PKG
                    + "' AND apk_path=" + quote(args[1]));
                System.out.println("EXTRA_SCOPES=" + extraScopes);
                System.out.println("LSPOSED_BRIDGE_STATE " + layout + " enabled=" + scalar(db, enabledQuery)
                    + " scopes=" + scopes + " apkMatches=" + apkMatches);
                return;
            }
            // Preserve an in-transaction digest of every other module row/scope.
            // A consistent SQLite backup includes committed WAL records; cp would not.
            Path backup = Path.of("/data/adb/gt8pro-mosey-bridge/lsposed-before-activation-" + System.currentTimeMillis() + ".db");
            db.execSQL("VACUUM INTO " + quote(backup.toString()));
            Files.setPosixFilePermissions(backup, java.nio.file.attribute.PosixFilePermissions.fromString("rw-------"));
            db.beginTransaction();
            try {
                String before = otherRowsDigest(db, layout);
                for (String sql : statements(layout, args[1])) db.execSQL(sql);
                String enabled = layout.equals("modern")
                    ? "SELECT enabled FROM modules_state WHERE module_pkg_name='" + PKG + "' AND user_id=0"
                    : "SELECT enabled FROM modules WHERE module_pkg_name='" + PKG + "'";
                String owner = layout.equals("modern") ? "module_pkg_name='" + PKG + "'"
                    : "mid=(SELECT mid FROM modules WHERE module_pkg_name='" + PKG + "')";
                if (scalar(db, enabled) != 1 || scalar(db, "SELECT COUNT(*) FROM scope WHERE " + owner
                        + " AND user_id=0 AND app_pkg_name IN ('com.google.android.gms','com.google.android.mosey')") != 2)
                    throw new IllegalStateException("LSPosed activation verification failed");
                if (!before.equals(otherRowsDigest(db, layout)))
                    throw new IllegalStateException("other_module_rows_changed");
                if (scalar(db, "SELECT COUNT(*) FROM scope WHERE " + owner) != 2)
                    throw new IllegalStateException("scope_set_not_exact");
                db.setTransactionSuccessful();
            } finally { db.endTransaction(); }
            System.out.println("LSPOSED_BRIDGE_ENABLED " + layout);
            System.out.println("EXACT_USER0_SCOPES=2");
            System.out.println("OTHER_MODULE_ROWS=UNCHANGED");
            System.out.println("BACKUP=CREATED_ROOT_PRIVATE");
            System.out.println("RUNTIME_RELOAD=REQUIRED");
        }
    }
}
