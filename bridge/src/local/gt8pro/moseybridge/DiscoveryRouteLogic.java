package local.gt8pro.moseybridge;
import java.net.*;import java.util.*;
/** No I/O. Preserve original choices unless the exact observed discovery route is eligible. */
final class DiscoveryRouteLogic {
 static boolean target(URI uri){return targetFor(uri,false);}
 static boolean targetSend(URI uri){return targetFor(uri,true);}
 private static boolean targetFor(URI uri,boolean send){
  if(uri==null||!"https".equalsIgnoreCase(uri.getScheme())||!(send?("/Ask".equals(uri.getRawPath())||"/Upload".equals(uri.getRawPath())):"/Discover".equals(uri.getRawPath()))
   ||uri.getPort()<1||uri.getPort()>65535||uri.getRawUserInfo()!=null||uri.getRawQuery()!=null||uri.getRawFragment()!=null)return false;
  String host=uri.getHost();if(host==null)return false;
  if(host.startsWith("[")&&host.endsWith("]"))host=host.substring(1,host.length()-1);
  if(host.length()<6||host.length()>39||!host.matches("[0-9a-fA-F:]+"))return false;
  String[] halves=host.split("::",-1);if(halves.length>2)return false;
  int total=0,first=-1;
  for(String half:halves){if(half.isEmpty())continue;for(String group:half.split(":",-1)){
   if(group.isEmpty()||group.length()>4)return false;
   int v=Integer.parseInt(group,16);if(first<0)first=v;total++;
  }}
  return !host.startsWith(":")&&first>=0xfe80&&first<=0xfebf&&(halves.length==2?total<8:total==8);
 }
 static boolean sameOrigin(URI request,URI route){
  return request!=null&&route!=null&&request.getScheme()!=null&&request.getHost()!=null
   &&request.getScheme().equalsIgnoreCase(route.getScheme())&&request.getHost().equalsIgnoreCase(route.getHost())&&request.getPort()==route.getPort();
 }
 static List<Proxy> adjustSend(boolean enabled,boolean active,int slot,URI uri,List<Proxy> original){
  if(enabled&&active&&slot>=1&&slot<=4&&targetSend(uri)&&original!=null&&original.size()==1&&original.get(0)!=null&&original.get(0).type()==Proxy.Type.HTTP)return Collections.singletonList(Proxy.NO_PROXY);
  return original;
 }
 static List<Proxy> adjust(boolean enabled,boolean active,int slot,URI uri,List<Proxy> original){
  if(enabled&&active&&slot>=1&&slot<=8&&target(uri)&&original!=null&&original.size()==1
   &&original.get(0)!=null&&original.get(0).type()==Proxy.Type.HTTP)return Collections.singletonList(Proxy.NO_PROXY);
  return original;
 }
}
