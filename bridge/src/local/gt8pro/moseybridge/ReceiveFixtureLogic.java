package local.gt8pro.moseybridge;
final class ReceiveFixtureLogic {
 static String classify(int count,String name,Long bytes,String type,String sender){
  if(count!=1)return "NOT_SINGLE_FILE";
  if(!"GT8Pro-AirDrop-082-MacToPhone.txt".equals(name))return "NAME_MISMATCH";
  if(bytes==null||bytes.longValue()!=8192)return "SIZE_MISMATCH";
  if(type==null||type.length()>128||!type.matches("[A-Za-z0-9][A-Za-z0-9._-]*"))return "TYPE_UNCONFIRMED";
  if("public.folder".equals(type))return "FOLDER";
  if(!"GT8Pro Test Mac".equals(sender)&&!"GT8Pro Test Sender".equals(sender))return "SENDER_MISMATCH";
  return "MATCH";
 }
}
