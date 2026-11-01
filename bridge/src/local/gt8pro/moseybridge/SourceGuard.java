package local.gt8pro.moseybridge;

import android.content.pm.ApplicationInfo;
import android.os.SystemClock;
import java.io.File;
import java.io.FileInputStream;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.util.*;

/** Check the defining loader; never open a new target DexFile or run target code. */
final class SourceGuard {
    static final String GMS_SHA="0a0af2a2c44c459a0dded52cb7e176704d640ae738980d12360697cf96c8da4e";
    static final String MOSEY_SHA="7ab2deaea6c9c2bdd5ba0f935d6143c115f5ceb11cb8b63066496ad27a28da49";
    private SourceGuard() {}
    static void time(long deadline) throws Exception {
        if (SystemClock.elapsedRealtime()>=deadline) throw new Exception("DEADLINE");
    }
    static void hash(ApplicationInfo info, String expected, long deadline) throws Exception {
        hashFile(new File(info.sourceDir).getCanonicalFile(),expected,deadline);
        if(MOSEY_SHA.equals(expected)){
            Map<String,String> splits=resourceSplits();
            if(info.splitSourceDirs==null||info.splitSourceDirs.length!=4)throw new Exception("APK_SPLITS");
            Set<String> seen=new HashSet<>();
            for(String p:info.splitSourceDirs){File f=new File(p).getCanonicalFile();String h=splits.get(f.getName());if(h==null||!seen.add(f.getName()))throw new Exception("APK_SPLITS");hashFile(f,h,deadline);}
        }
    }
    private static Map<String,String> resourceSplits(){
        Map<String,String> splits=new HashMap<>();
        splits.put("split_config.arm64_v8a.apk","3f7c689c95a54cda1fd05641e704b00daf22afdae5935ea065f038f13342ee75");
        splits.put("split_config.en.apk","cf362969b16c1aac860e86deff8b425fcc50e3e68d6a1d4df5be686dbc79a9b7");
        splits.put("split_config.xxxhdpi.apk","ff92800edf0de128e06c6fd38c4ed85b4a936b09ff492b075015c702d768cb04");
        splits.put("split_config.zh.apk","fe0cf4bc4f50e91a63e877d5db9f8e063e735b8e85e04031d81dae55879dd9fa");
        return splits;
    }
    static void hashFile(File base,String expected,long deadline) throws Exception {
        MessageDigest sha=MessageDigest.getInstance("SHA-256");
        long before=base.length(), modified=base.lastModified();
        if(before<1||before>256L*1024*1024)throw new Exception("APK_SIZE");
        try(FileInputStream in=new FileInputStream(base)) {
            byte[] b=new byte[65536];int n;
            while((n=in.read(b))!=-1){time(deadline);sha.update(b,0,n);}
        }
        if(base.length()!=before||base.lastModified()!=modified)throw new Exception("APK_CHANGED");
        StringBuilder hex=new StringBuilder();
        for(byte b:sha.digest())hex.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
        if(!expected.equals(hex.toString()))throw new Exception("APK_HASH");
    }
    static void owner(Class<?> type, ApplicationInfo info, long deadline) throws Exception {
        ClassLoader loader=type.getClassLoader();
        Class<?> baseLoader=Class.forName("dalvik.system.BaseDexClassLoader",false,null);
        if(!baseLoader.isInstance(loader))throw new Exception("LOADER_TYPE");
        File base=new File(info.sourceDir).getCanonicalFile();
        Set<File> allowed=new HashSet<>();allowed.add(base);
        if(info.splitSourceDirs!=null)for(String s:info.splitSourceDirs)allowed.add(new File(s).getCanonicalFile());
        Object paths=field(baseLoader,"pathList").get(loader);
        Object elements=field(paths.getClass(),"dexElements").get(paths);
        if(elements==null||Array.getLength(elements)<1||Array.getLength(elements)>32)
            throw new Exception("DEX_ELEMENTS");
        Set<File> seen=new HashSet<>();int definitions=0;boolean fromBase=false;
        Class<?> dexType=Class.forName("dalvik.system.DexFile",false,null);
        Method getName=dexType.getMethod("getName"), entries=dexType.getMethod("entries");
        for(int i=0;i<Array.getLength(elements);i++) {
            time(deadline);
            Object element=Array.get(elements,i), dex=field(element.getClass(),"dexFile").get(element);
            if(dex==null){
                // Android puts verified resource-only APKs in dexElements with null dexFile.
                // Admit only the four pinned, independently inspected no-DEX split files.
                Object raw=field(element.getClass(),"path").get(element);
                if(!(raw instanceof File))throw new Exception("DEX_MISSING");
                File resource=((File)raw).getCanonicalFile();
                String expected=resourceSplits().get(resource.getName());
                if(expected==null||!allowed.contains(resource)||resource.equals(base)
                        ||!resource.getParentFile().equals(base.getParentFile())||!seen.add(resource))
                    throw new Exception("DEX_SOURCE");
                hashFile(resource,expected,deadline);
                continue;
            }
            if(!dexType.isInstance(dex))throw new Exception("DEX_MISSING");
            Object rawName=getName.invoke(dex);
            if(!(rawName instanceof String))throw new Exception("DEX_NAME");
            File source=new File((String)rawName).getCanonicalFile();
            if(!allowed.contains(source)||!seen.add(source))throw new Exception("DEX_SOURCE");
            Object raw=entries.invoke(dex);
            if(!(raw instanceof Enumeration))throw new Exception("DEX_ENTRIES");
            Enumeration<?> names=(Enumeration<?>)raw;int count=0;
            while(names.hasMoreElements()) {
                if((++count&255)==0)time(deadline);
                if(count>400000)throw new Exception("CLASS_BUDGET");
                Object name=names.nextElement();
                if(type.getName().equals(name)){definitions++;fromBase=source.equals(base);}
            }
        }
        if(definitions!=1||!fromBase)throw new Exception("CLASS_SOURCE_AMBIGUOUS");
    }
    private static Field field(Class<?> c,String name) throws Exception {
        Field f=c.getDeclaredField(name);f.setAccessible(true);return f;
    }
}
