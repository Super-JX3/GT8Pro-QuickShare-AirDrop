package local.gt8pro.moseybridge;

/** Main-user package identity for the synthetic test provider. */
final class UidPolicy {
 static boolean validTarget(int own,int target,String[] owners){
  return own>=10000&&own<20000&&target>=10000&&target<20000&&own!=target
    &&owners!=null&&owners.length==1&&"com.google.android.mosey".equals(owners[0]);
 }
}
