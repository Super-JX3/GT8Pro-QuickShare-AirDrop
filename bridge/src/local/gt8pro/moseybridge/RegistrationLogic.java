package local.gt8pro.moseybridge;
/** Fixed classification only; never prints an exception message or task value. */
public final class RegistrationLogic {
 private RegistrationLogic(){}
 public static String code(int value){return value>=-1&&value<=999?Integer.toString(value):"OTHER";}
 public static String state(boolean complete,boolean cancelled,boolean error){
  if(!complete)return "PENDING";
  if(cancelled)return "CANCELLED";
  return error?"FAILED":"SUCCESS";
 }
 public static String errorKind(Exception error){
  if(error instanceof UnsupportedOperationException)return "UNSUPPORTED";
  if(error instanceof SecurityException)return "SECURITY";
  return "OTHER";
 }
}
