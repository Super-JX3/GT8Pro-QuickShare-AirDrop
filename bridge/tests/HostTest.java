package local.gt8pro.moseybridge;
import android.content.pm.ApplicationInfo;
import android.os.SystemClock;
import dalvik.system.BaseDexClassLoader;
import dalvik.system.DexFile;
import java.io.File;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

public final class HostTest {
 static int checks;
 static void check(boolean b,String s){checks++;if(!b)throw new AssertionError(s);}
 interface Work{void run()throws Exception;}
 static void rejects(Work w,String s)throws Exception{
  boolean rejected=false;try{w.run();}catch(Exception e){rejected=true;}check(rejected,s);
 }
 public static final class Element{public DexFile dexFile;public File path;Element(DexFile d){dexFile=d;}Element(File p){path=p;}}
 public static final class PathsFixture{public Element[] dexElements;PathsFixture(Element...e){dexElements=e;}}
 static ApplicationInfo info(File base,File...splits){
  ApplicationInfo i=new ApplicationInfo();i.sourceDir=base.getPath();i.splitSourceDirs=Arrays.stream(splits).map(File::getPath).toArray(String[]::new);return i;
 }
 static Class<?> owner(byte[] payload,Element...elements){
  BaseDexClassLoader l=new BaseDexClassLoader(HostTest.class.getClassLoader());
  l.pathList=new PathsFixture(elements);return l.make("fixture.Target",payload);
 }
 static Element element(File file,String...names){return new Element(new DexFile(file.getPath(),names));}
 static void sources(Path root,byte[] payload)throws Exception{
  File base=root.resolve("base.apk").toFile(),split=root.resolve("split.apk").toFile(),other=root.resolve("dynamic.apk").toFile();
  Files.write(base.toPath(),new byte[]{1,2,3});Files.write(split.toPath(),new byte[]{4});Files.write(other.toPath(),new byte[]{5});
  SystemClock.now=1;
  SourceGuard.owner(owner(payload,element(base,"fixture.Target")),info(base),100);checks++;
  SourceGuard.owner(owner(payload,element(base,"fixture.Target"),element(split,"fixture.Other")),info(base,split),100);checks++;
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Target"),element(split,"fixture.Target")),info(base,split),100),"duplicate target cannot be admitted");
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Target"),element(other,"fixture.Other")),info(base,split),100),"dynamic source rejected");
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Other"),element(split,"fixture.Target")),info(base,split),100),"split-defined target rejected");
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Target"),element(base,"fixture.Other")),info(base),100),"duplicate source rejected");
  rejects(()->SourceGuard.owner(owner(payload),info(base),100),"empty defining loader rejected");
  rejects(()->SourceGuard.owner(owner(payload,new Element((DexFile)null)),info(base),100),"missing dex rejected");
  rejects(()->SourceGuard.owner(HostTest.class,info(base),100),"ordinary class loader rejected");
  File resource=root.resolve("split_config.en.apk").toFile();
  Files.write(resource.toPath(),"public-resource-fixture".getBytes(java.nio.charset.StandardCharsets.UTF_8));
  SourceGuard.owner(owner(payload,element(base,"fixture.Target"),new Element(resource)),info(base,resource),100);checks++;
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Target"),new Element(resource)),info(base),100),"unlisted resource rejected");
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Target"),new Element(split)),info(base,split),100),"arbitrary no-dex resource rejected");
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Target"),new Element(resource),new Element(resource)),info(base,resource),100),"duplicate resource rejected");
  Files.write(resource.toPath(),new byte[]{1,2,3});
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Target"),new Element(resource)),info(base,resource),100),"changed pinned resource rejected");

  SystemClock.now=100;
  rejects(()->SourceGuard.owner(owner(payload,element(base,"fixture.Target")),info(base),100),"source deadline enforced");
  SystemClock.now=1;
  String sha=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(new byte[]{1,2,3}));
  SourceGuard.hash(info(base),sha,100);checks++;
  rejects(()->SourceGuard.hash(info(base),"wrong",100),"hash mismatch rejected");
  SystemClock.now=100;rejects(()->SourceGuard.hash(info(base),sha,100),"hash deadline enforced");
  SystemClock.now=1;Files.write(base.toPath(),new byte[0]);rejects(()->SourceGuard.hash(info(base),sha,100),"empty APK rejected");
 }
 static void decisions(){
  String fw="RMX5200_16.0.10.501(CN01)";
  check(HookLogic.target("com.google.android.gms","com.google.android.gms",12345,36,fw),"GMS main accepted");
  check(HookLogic.target("com.google.android.mosey","com.google.android.mosey",12345,36,fw),"Mosey main accepted");
  for(int uid:new int[]{0,9999,100000,99912345})check(!HookLogic.target("com.google.android.gms","com.google.android.gms",uid,36,fw),"wrong user/UID rejected");
  check(!HookLogic.target("android","android",12345,36,fw),"system process excluded");
  check(!HookLogic.target("com.google.android.gms","com.google.android.gms.persistent",12345,36,fw),"unverified sibling process excluded");
  check(!HookLogic.target("com.google.android.gms","com.google.android.gms",12345,37,fw),"changed SDK excluded");
  check(!HookLogic.target("com.google.android.gms","com.google.android.gms",12345,36,"other"),"changed firmware excluded");
  check(HookLogic.enable(true,true,1,2,false,Boolean.FALSE,0),"successful false can change");
  check(!HookLogic.enable(false,true,1,2,false,Boolean.FALSE,0),"observer cannot mutate");
  check(!HookLogic.enable(true,false,1,2,false,Boolean.FALSE,0),"partial installation inert");
  check(!HookLogic.enable(true,true,2,2,false,Boolean.FALSE,0),"expired gate inert");
  check(!HookLogic.enable(true,true,1,2,true,Boolean.FALSE,0),"exception preserved");
  for(Object value:new Object[]{Boolean.TRUE,null,"false",Integer.valueOf(0)})
   check(!HookLogic.enable(true,true,1,2,false,value,0),"non-false result preserved");
  for(int n:new int[]{-1,1,2})check(!HookLogic.enable(true,true,1,2,false,Boolean.FALSE,n),"unexpected arguments rejected");
  AtomicInteger calls=new AtomicInteger();Object real=new Object();
  HookLogic.Lookup good=()->{calls.incrementAndGet();return new HookLogic.BinderView(){
   public boolean alive(){return true;}public String descriptor(){return HookLogic.DESCRIPTOR;}public Object value(){return real;}};};
  check(!HookLogic.lookup(HookLogic.INSTANCE,false,true,1,2,good).intercept,"observer never looks up");
  check(!HookLogic.lookup("other",true,true,1,2,good).intercept,"other service untouched");
  check(!HookLogic.lookup(HookLogic.INSTANCE,true,false,1,2,good).intercept,"unarmed lookup untouched");
  check(!HookLogic.lookup(HookLogic.INSTANCE,true,true,2,2,good).intercept,"expired lookup untouched");
  check(calls.get()==0,"no producer calls outside admission");
  HookLogic.Decision d=HookLogic.lookup(HookLogic.INSTANCE,true,true,1,2,good);
  check(d.intercept&&d.binder==real&&calls.get()==1,"only real binder returned");
  check(HookLogic.lookup(HookLogic.INSTANCE,true,true,1,2,()->null).binder==null,"absent binder not synthesized");
  d=HookLogic.lookup(HookLogic.INSTANCE,true,true,1,2,()->{throw new Exception("PRIVATE_IDENTIFIER");});
  check(!d.intercept&&d.binder==null&&d.event.equals("LOOKUP_ERROR"),"lookup error fails closed without message");
  for(boolean alive:new boolean[]{false,true}){
   d=HookLogic.lookup(HookLogic.INSTANCE,true,true,1,2,()->new HookLogic.BinderView(){
    public boolean alive(){return alive;}public String descriptor(){return "wrong";}public Object value(){return real;}});
   check(!d.intercept&&d.binder==null,"dead or wrong descriptor leaves original call");
  }
 }
 static HookLogic.BinderView view(boolean alive,String descriptor,Object value){
  return new HookLogic.BinderView(){public boolean alive(){return alive;}public String descriptor(){return descriptor;}public Object value(){return value;}};
 }
 static void probes(){
  AtomicInteger calls=new AtomicInteger();Object real=new Object();
  HookLogic.Lookup good=()->{calls.incrementAndGet();return view(true,HookLogic.DESCRIPTOR,real);};
  check(ProbeLogic.inspect(false,1,2,good).equals("EXPIRED"),"unarmed explicit probe does nothing");
  check(ProbeLogic.inspect(true,2,2,good).equals("EXPIRED"),"expired explicit probe does nothing");
  check(calls.get()==0,"no probe producer outside admission");
  check(ProbeLogic.inspect(true,1,2,good).equals("REAL_BINDER_VERIFIED"),"actual binder verified");
  check(calls.get()==1,"probe producer called once");
  int before=calls.get();
  for(Object declaration:new Object[]{Boolean.TRUE,null,"false",Integer.valueOf(0)}){
   HookLogic.Decision d=HookLogic.lookupDeclared(HookLogic.INSTANCE,true,true,1,2,declaration,good);
   check(!d.intercept&&d.binder==null,"only explicit false declaration admitted");
  }
  check(calls.get()==before,"no lookup when already declared or unknown");
  check(HookLogic.lookupDeclared(HookLogic.INSTANCE,true,true,1,2,Boolean.FALSE,good).binder==real,"undeclared real verified binder admitted");
  check(!HookLogic.lookupDeclared(HookLogic.INSTANCE,true,true,1,2,Boolean.FALSE,()->null).intercept,"absent service preserves original path");

  check(ProbeLogic.inspect(true,1,2,()->null).equals("REAL_BINDER_ABSENT"),"probe no binder");
  check(ProbeLogic.inspect(true,1,2,()->view(true,HookLogic.DESCRIPTOR,null)).equals("REAL_BINDER_ABSENT"),"probe no payload");
  check(ProbeLogic.inspect(true,1,2,()->view(false,HookLogic.DESCRIPTOR,real)).equals("REAL_BINDER_DEAD"),"probe dead binder");
  check(ProbeLogic.inspect(true,1,2,()->view(true,"OTHER",real)).equals("DESCRIPTOR_MISMATCH"),"probe wrong descriptor");
  check(ProbeLogic.inspect(true,1,2,()->{throw new SecurityException("PRIVATE_IDENTIFIER");}).equals("SECURITY_DENIED"),"security categorized privately");
  check(ProbeLogic.inspect(true,1,2,()->{throw new Exception("PRIVATE_IDENTIFIER");}).equals("LOOKUP_ERROR"),"other failure categorized privately");
 }
 public static void main(String[] a)throws Exception{
  check(RegistrationLogic.state(false,false,false).equals("PENDING"),"pending task is not success");
  check(RegistrationLogic.state(true,false,false).equals("SUCCESS"),"completed success");
  check(RegistrationLogic.state(true,false,true).equals("FAILED"),"completed failure");
  check(RegistrationLogic.state(true,true,false).equals("CANCELLED"),"cancelled task");
  check(RegistrationLogic.errorKind(new UnsupportedOperationException("PRIVATE")).equals("UNSUPPORTED"),"feature failure private");
  check(RegistrationLogic.errorKind(new SecurityException("PRIVATE")).equals("SECURITY"),"security failure private");
  check(RegistrationLogic.errorKind(new Exception("PRIVATE")).equals("OTHER"),"other failure private");
  check(RegistrationLogic.code(-1).equals("-1"),"lowest admitted status");
  check(RegistrationLogic.code(16).equals("16"),"connection domain status");
  check(RegistrationLogic.code(999).equals("999"),"largest admitted status");
  check(RegistrationLogic.code(1000).equals("OTHER"),"large unexpected numbers redacted");
  check(RegistrationLogic.code(-2).equals("OTHER"),"unexpected negative redacted");
  decisions();probes();sources(Files.createTempDirectory("gt8-host-"),Files.readAllBytes(Path.of(a[0])));
  System.out.println("HOST_GUARD_CHECKS_PASS="+checks);
  System.out.println("ANDROID_APKS_EXECUTED=false");
 }
}
