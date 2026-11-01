package local.gt8pro.moseybridge;
import java.net.*;import java.util.*;
public final class RouteLogicTest {
 static int n;static void check(boolean v){n++;if(!v)throw new AssertionError("route "+n);}
 public static void main(String[] args)throws Exception{
  for(String s:new String[]{"https://[fe80::1]:443/Discover","https://[febf:1:2:3:4:5:6:7]:1/Discover","https://[FeA0::abcd]:65535/Discover"})check(DiscoveryRouteLogic.target(URI.create(s)));
  for(String s:new String[]{"http://[fe80::1]:443/Discover","https://[fe80::1]:443/Ask","https://[fe80::1]:443/Upload","https://[fe80::1]:443/Discovery","https://[fe80::1]/Discover","https://[fe80::1]:0/Discover","https://[fe80::1]:65536/Discover","https://[fec0::1]:443/Discover","https://[::1]:443/Discover","https://[2001:db8::1]:443/Discover","https://example.com:443/Discover","https://127.0.0.1:443/Discover","https://[fe80::1%25mosey0]:443/Discover","https://user:pw@[fe80::1]:443/Discover","https://[fe80::1]:443/Discover?x=1","https://[fe80::1]:443/Discover#x"})check(!DiscoveryRouteLogic.target(URI.create(s)));
  check(!DiscoveryRouteLogic.target(null));
  Proxy http=new Proxy(Proxy.Type.HTTP,InetSocketAddress.createUnresolved("local.invalid",1234));Proxy socks=new Proxy(Proxy.Type.SOCKS,InetSocketAddress.createUnresolved("local.invalid",1234));
  URI target=URI.create("https://[fe80::1]:443/Discover");List<Proxy> original=Collections.singletonList(http);
  check(DiscoveryRouteLogic.adjust(true,true,1,target,original).equals(Collections.singletonList(Proxy.NO_PROXY)));check(original.size()==1&&original.get(0)==http);
  check(DiscoveryRouteLogic.adjust(false,true,1,target,original)==original);check(DiscoveryRouteLogic.adjust(true,false,1,target,original)==original);
  for(int invalid:new int[]{-1,0,9})check(DiscoveryRouteLogic.adjust(true,true,invalid,target,original)==original);
  check(DiscoveryRouteLogic.adjust(true,true,8,target,original).get(0)==Proxy.NO_PROXY);
  check(DiscoveryRouteLogic.adjust(true,true,1,URI.create("https://example.com:443/Discover"),original)==original);
  for(List<Proxy> choices:Arrays.asList(null,Collections.<Proxy>emptyList(),Collections.singletonList(Proxy.NO_PROXY),Collections.singletonList(socks),Arrays.asList(http,socks),Collections.<Proxy>singletonList(null)))check(DiscoveryRouteLogic.adjust(true,true,1,target,choices)==choices);
  URI request=URI.create("https://[fe80::1]:1234/Discover"),origin=URI.create("https://[fe80::1]:1234/");check(DiscoveryRouteLogic.sameOrigin(request,origin));
  check(!DiscoveryRouteLogic.sameOrigin(request,URI.create("https://[fe80::2]:1234/")));check(!DiscoveryRouteLogic.sameOrigin(request,URI.create("https://[fe80::1]:1235/")));check(!DiscoveryRouteLogic.sameOrigin(request,URI.create("http://[fe80::1]:1234/")));check(!DiscoveryRouteLogic.sameOrigin(request,null));check(!DiscoveryRouteLogic.sameOrigin(null,origin));
  for(String path:new String[]{"/Ask","/Upload"}){
   URI local=URI.create("https://[fe80::1]:1234"+path);check(DiscoveryRouteLogic.targetSend(local));check(DiscoveryRouteLogic.adjustSend(true,true,1,local,original).get(0)==Proxy.NO_PROXY);check(DiscoveryRouteLogic.adjustSend(true,true,4,local,original).get(0)==Proxy.NO_PROXY);
   check(DiscoveryRouteLogic.adjustSend(false,true,1,local,original)==original);check(DiscoveryRouteLogic.adjustSend(true,false,1,local,original)==original);check(DiscoveryRouteLogic.adjustSend(true,true,5,local,original)==original);
   check(DiscoveryRouteLogic.adjustSend(true,true,1,URI.create("https://example.com:1234"+path),original)==original);check(DiscoveryRouteLogic.adjustSend(true,true,1,URI.create("http://[fe80::1]:1234"+path),original)==original);
  }
  check(!DiscoveryRouteLogic.targetSend(URI.create("https://[fe80::1]:1234/Discover")));check(!DiscoveryRouteLogic.targetSend(URI.create("https://[fe80::1]:1234/Other")));
  System.out.println("DISCOVERY_ROUTE_GUARD_CHECKS_PASS="+n);
 }
}
