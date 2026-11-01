package local.gt8pro.moseybridge;
/** Read-only diagnosis. No application MethodHookParam, result replacement or cache. */
public final class ProbeLogic {
 private ProbeLogic(){}
 public static String inspect(boolean active,long now,long deadline,HookLogic.Lookup lookup){
  if(!active||now>=deadline)return "EXPIRED";
  try {
   HookLogic.BinderView b=lookup.check();
   if(b==null||b.value()==null)return "REAL_BINDER_ABSENT";
   if(!b.alive())return "REAL_BINDER_DEAD";
   if(!HookLogic.DESCRIPTOR.equals(b.descriptor()))return "DESCRIPTOR_MISMATCH";
   return "REAL_BINDER_VERIFIED";
  }catch(SecurityException denied){return "SECURITY_DENIED";}
  catch(Exception unavailable){return "LOOKUP_ERROR";}
 }
}
