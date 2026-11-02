import android.content.Context;
import android.content.pm.*;
import android.os.*;
import java.io.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.*;

/** Fixed-target framework metadata queries only; no grant, app-code loading, or app data reads. */
public final class GT8ProMosey60715Profile {
 static final String PKG="com.google.android.mosey";
 static final Map<String,String> HASHES=new HashMap<>();
 static {
  HASHES.put("base.apk","7ab2deaea6c9c2bdd5ba0f935d6143c115f5ceb11cb8b63066496ad27a28da49");
  HASHES.put("split_config.arm64_v8a.apk","3f7c689c95a54cda1fd05641e704b00daf22afdae5935ea065f038f13342ee75");
  HASHES.put("split_config.en.apk","cf362969b16c1aac860e86deff8b425fcc50e3e68d6a1d4df5be686dbc79a9b7");
  HASHES.put("split_config.xxxhdpi.apk","ff92800edf0de128e06c6fd38c4ed85b4a936b09ff492b075015c702d768cb04");
  HASHES.put("split_config.zh.apk","fe0cf4bc4f50e91a63e877d5db9f8e063e735b8e85e04031d81dae55879dd9fa");
 }
 static void require(boolean b,String code)throws Exception {if(!b)throw new Exception(code);}
 static String digest(byte[] data)throws Exception {return hex(MessageDigest.getInstance("SHA-256").digest(data));}
 static String hex(byte[] b){StringBuilder s=new StringBuilder();for(byte v:b)s.append(String.format(Locale.ROOT,"%02x",v&255));return s.toString();}
 static String hash(File f)throws Exception {
  require(f.isFile()&&f.length()>0&&f.length()<256L*1024*1024,"CODE_SIZE");
  MessageDigest d=MessageDigest.getInstance("SHA-256");long size=f.length(),time=f.lastModified();
  try(InputStream in=new FileInputStream(f)){byte[] buf=new byte[65536];int n;while((n=in.read(buf))!=-1)d.update(buf,0,n);}
  require(size==f.length()&&time==f.lastModified(),"CODE_CHANGED");return hex(d.digest());
 }
 public static void main(String[] args) {
  try {
   require(args.length==0&&android.os.Process.myUid()==0&&Build.VERSION.SDK_INT==36&&Build.MODEL.equals("RMX5200")&&Build.DISPLAY.equals("RMX5200_16.0.10.501(CN01)"),"TARGET");
   if(Looper.myLooper()==null)Looper.prepareMainLooper();
   Class<?> at=Class.forName("android.app.ActivityThread");
   Object thread=at.getDeclaredMethod("systemMain").invoke(null);
   Method get=at.getDeclaredMethod("getSystemContext");get.setAccessible(true);
   Context context=(Context)get.invoke(thread);PackageManager pm=context.getPackageManager();
   PackageInfo p=pm.getPackageInfo(PKG,PackageManager.GET_PERMISSIONS|PackageManager.GET_SIGNING_CERTIFICATES);
   ApplicationInfo a=p.applicationInfo;
   require(p.getLongVersionCode()==60715&&a.uid>=10000&&a.uid<20000&&a.targetSdkVersion==37,"PACKAGE_VERSION_UID");
   require((a.flags&ApplicationInfo.FLAG_SYSTEM)!=0&&(a.flags&ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)!=0,"SYSTEM_UPDATE");
   String[] owners=pm.getPackagesForUid(a.uid);require(owners!=null&&owners.length==1&&PKG.equals(owners[0]),"UID_OWNER");
   Signature[] sig=p.signingInfo.getApkContentsSigners();require(sig.length==1&&digest(sig[0].toByteArray()).equals("82f90326951d14e08010b2a26cce329be2b09e74752158b7640e04a544676878"),"SIGNER");
   require(a.splitSourceDirs!=null&&a.splitSourceDirs.length==4,"SPLITS");
   List<String> files=new ArrayList<>();files.add(a.sourceDir);files.addAll(Arrays.asList(a.splitSourceDirs));
   Set<String> names=new HashSet<>();
   for(String file:files){File f=new File(file).getCanonicalFile();require(f.getPath().startsWith("/data/app/")&&names.add(f.getName())&&Objects.equals(HASHES.get(f.getName()),hash(f)),"CODE_HASH");}
   require(names.equals(HASHES.keySet()),"CODE_SET");
   System.out.println("CURRENT_CODE_PROFILE=PASS");System.out.println("CURRENT_GOOGLE_SIGNER=PASS");System.out.println("CURRENT_MOSEY_UID="+a.uid);
   Method priv=ApplicationInfo.class.getDeclaredMethod("isPrivilegedApp");priv.setAccessible(true);
   System.out.println("CURRENT_PRIVILEGED="+priv.invoke(a));
   Set<String> requested=new HashSet<>(Arrays.asList(p.requestedPermissions));
   for(String shortName:new String[]{"NETWORK_FACTORY","CREATE_APP_SPECIFIC_NETWORK","BLUETOOTH_PRIVILEGED","CONNECTIVITY_USE_RESTRICTED_NETWORKS","MANAGE_WIFI_INTERFACES","LOCATION_HARDWARE","INTERNET","ACCESS_LOCAL_NETWORK","BLUETOOTH_SCAN","BLUETOOTH_ADVERTISE","NEARBY_WIFI_DEVICES","ACCESS_FINE_LOCATION","ACCESS_COARSE_LOCATION","ACCESS_BACKGROUND_LOCATION"}) {
    String name="android.permission."+shortName;String protection="UNDEFINED";
    try{protection=Integer.toString(pm.getPermissionInfo(name,0).protectionLevel);}catch(PackageManager.NameNotFoundException ignored){}
    System.out.println("CURRENT_PERMISSION="+shortName+" REQUESTED="+(requested.contains(name)?"YES":"NO")+" GRANTED="+(pm.checkPermission(name,PKG)==PackageManager.PERMISSION_GRANTED?"YES":"NO")+" PROTECTION="+protection);
   }
   System.out.println("CURRENT_PROFILE_RESULT=PASS");
  }catch(Throwable e){System.out.println("CURRENT_PROFILE_RESULT=UNCONFIRMED");System.exit(1);}
 }
}
