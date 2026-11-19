import java.io.File;
import java.io.FileInputStream;
import java.security.MessageDigest;
import java.util.*;
import moseyPLK.client.GmsDexFile;
/** Offline proof of selected DEX references; never executes target code. */
public final class GateProof {
 static final String SHA="8395c70a5e4ffbe2712aea7e1045d700b282f0a67d19b80686c595c991f12112";
 static void check(boolean ok,String name){if(!ok)throw new IllegalStateException(name);}
 static String digest(File f)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");try(FileInputStream in=new FileInputStream(f)){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)d.update(b,0,n);}StringBuilder s=new StringBuilder();for(byte b:d.digest())s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}
 static GmsDexFile.Method m(GmsDexFile d,String name)throws Exception{GmsDexFile.Method x=d.findMethod(name);check(x!=null,"missing "+name);return x;}
 static boolean ref(GmsDexFile.Method m,String name)throws Exception{for(GmsDexFile.Instruction i:m.code().instructions)if(name.equals(i.reference))return true;return false;}
 static boolean inOrder(GmsDexFile.Method m,String...refs)throws Exception{int at=0;for(GmsDexFile.Instruction i:m.code().instructions)if(at<refs.length&&refs[at].equals(i.reference))at++;return at==refs.length;}
 public static void main(String[] args)throws Exception{check(args.length==1,"expected APK path");File apk=new File(args[0]);check(SHA.equals(digest(apk)),"unknown APK");
  try(GmsDexFile d=GmsDexFile.readApk(apk)){
   String service="Lcom/google/android/gms/nearby/sharing/NearbySharingChimeraService;";
   GmsDexFile.Method init=m(d,service+"-><init>()V");
   check(inOrder(init,"Lelbo;","Lelbo;-><init>()V","Liest;->a(Lieso;)Lieso;",service+"->av:Lieso;"),"memoized gate assignment");
   GmsDexFile.Method gate=m(d,"Lelbo;->lD()Ljava/lang/Object;");
   check(inOrder(gate,"Lkekx;->O()Z","Lkekx;->M()Z","Ljava/lang/Boolean;->valueOf(Z)Ljava/lang/Boolean;"),"two flag source");
   List<GmsDexFile.Instruction> gi=gate.code().instructions;
   check(gi.size()==17 && gi.get(6).opname.equals("const/4") && gi.get(6).literal==1 && gi.get(7).opname.equals("if-nez") && gi.get(7).target==26 && gi.get(12).opname.equals("if-nez") && gi.get(12).target==26 && gi.get(13).opname.equals("const/4") && gi.get(13).literal==0 && gi.get(14).pc==26,"gate OR control flow");
   GmsDexFile.Method maker=m(d,"Liest;->a(Lieso;)Lieso;");check(ref(maker,"Liesr;")&&ref(maker,"Liesq;"),"memoizer creation");
   GmsDexFile.Method memo=m(d,"Liesr;->lD()Ljava/lang/Object;");check(inOrder(memo,"Liesr;->b:Lieso;","Lieso;->lD()Ljava/lang/Object;","Liesr;->c:Ljava/lang/Object;","Liesr;->b:Lieso;","Liesr;->c:Ljava/lang/Object;"),"memoizer cache");
   List<GmsDexFile.Instruction> mi=memo.code().instructions;check(mi.get(1).opname.equals("if-eqz")&&mi.get(1).target==30&&mi.get(10).opname.equals("const/4")&&mi.get(10).literal==0&&mi.get(11).opname.equals("iput-object"),"cached read bypasses source");
   GmsDexFile.Method state=m(d,service+"->ac(Z)V");check(ref(state,service+"->av:Lieso;")&&ref(state,"Ljdhz;->c()V")&&ref(state,"Ljdhz;->b()V"),"registry gate");
  }
  check(SHA.equals(digest(apk)),"APK changed during inspection");System.out.println("GMS_GATE_STATIC_STRUCTURE=PASS");System.out.println("RUNTIME_CACHED_VALUE=UNCONFIRMED");
 }
}
